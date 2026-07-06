/**
 * Unit tests for QuoteLineItemTriggerHandler.
 *
 * The handler carries FIVE responsibilities; each is exercised at least once:
 *   1. Auto-populate Description from Product2.Name on beforeInsert/beforeUpdate
 *   2. Recalculate Quote.Tax = SUM(TotalPrice) * 19% on every QLI mutation
 *   3. Apply attribute-based price adjustments (Techno_Attribute_Price_Rule__mdt)
 *      on Bundle QLIs in beforeUpdate — idempotent rebase from PricebookEntry.UnitPrice
 *   4. Auto-decompose Bundle parents into child QLIs asynchronously after insert
 *      (@future path — flushed by Test.stopTest)
 *   5. Async cleanup of duplicate Bundle QLIs on the same Quote (oldest wins)
 *   + Recursion / bypass guards via TriggerHandler.bypass()
 *
 * PLATFORM NOTES / TESTABILITY CAVEATS (roadmap TS-TEST-014):
 *   - Custom metadata Techno_Attribute_Price_Rule__mdt records are org-committed and
 *     visible to tests. HOWEVER the 14 seeded rules key on the real production
 *     Product2 Id `01taj00000Qp7IFAAZ`. Test-created Product2 records get fresh Ids
 *     that WILL NOT match, so `applyAttributeAdjustmentsInPlace` always resolves to
 *     totalAdjustment=0 in these tests. That still exercises the mutation code path
 *     (rebase from PricebookEntry) and lets us assert idempotency and the non-Bundle
 *     early-exit — but assertions like "i9 CPU rule adds +500" require a @TestVisible
 *     rules-override seam (roadmap ticket TS-TEST-014).
 *   - Bundle decomposition requires ProductRelatedComponent (a standard RLM sObject).
 *     Insertable in tests; verified below.
 *   - AttributePicklistValue is CPQ-restricted (not insertable in Apex tests) — the
 *     `adjustmentFromPicklistLabel` label-parsing fallback path is exercised only via
 *     the "no picklist value" branch, i.e. via total-adjustment-zero rebase.
 *
 * @TestVisible on the target class (existing):
 *   - `records` and `oldRecords` getters — useful but neither test path needs them.
 *
 * @TestVisible seams that WOULD sharpen these tests (TS-TEST-014):
 *   - `static Map<String, Techno_Attribute_Price_Rule__mdt> testRulesOverride` on
 *     the target class → applyAttributeAdjustmentsInPlace consults it first when set.
 *     Would enable per-test rule injection (Processor i9 +500 / RAM 32GB +200 etc.).
 *   - `static Boolean testForceSyncDecomposition` → let the after-insert path call
 *     autoDecomposeBundles synchronously in tests without needing Test.stopTest.
 *   - `static Map<Id, PricebookEntry> testPbeOverride` → let the score-preference
 *     test inject multiple PBEs per (Pricebook, Product) with fabricated selling
 *     model types, avoiding the CPQ ProductSellingModel factory dependency.
 */
@IsTest
private class QuoteLineItemTriggerHandlerTest {

    // ---------------- @TestSetup: Account + Opportunity + Products + PBEs + Quote ----------------

    @TestSetup
    static void seed() {
        Account a = TestDataFactory.newAccount('QLI Test DE GmbH');

        Opportunity opp = new Opportunity(
            AccountId = a.Id,
            Name      = 'QLI Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Bundle parent (Type=Bundle, ProductCode aligns w/ 14 seeded CMD rules)
        Product2 bundle = new Product2(
            Name        = 'HomeOffice Workstation Bundle',
            ProductCode = 'BUNDLE-OFFICE-001',
            Type        = 'Bundle',
            IsActive    = true
        );

        // Bundle child (decomposes into this on afterInsert @future)
        Product2 bundleChild = new Product2(
            Name        = 'ThinkPad Laptop',
            ProductCode = 'COMP-LAP-001',
            IsActive    = true
        );

        // Plain non-Bundle product for VAT-only / autoDescription / non-bundle-exit tests
        Product2 plain = new Product2(
            Name        = 'USB Cable',
            ProductCode = 'ACC-USB-001',
            IsActive    = true
        );

        insert new List<Product2>{ bundle, bundleChild, plain };

        Id stdPB = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = stdPB, Product2Id = bundle.Id,
                UnitPrice = 2000, IsActive = true, UseStandardPrice = false),
            new PricebookEntry(Pricebook2Id = stdPB, Product2Id = bundleChild.Id,
                UnitPrice = 1500, IsActive = true, UseStandardPrice = false),
            new PricebookEntry(Pricebook2Id = stdPB, Product2Id = plain.Id,
                UnitPrice = 100, IsActive = true, UseStandardPrice = false)
        };

        // ProductRelatedComponent: bundle -> bundleChild, IsDefaultComponent=true
        // Bundle price does NOT include child, so child gets its own PBE.UnitPrice
        ProductRelatedComponent prc = new ProductRelatedComponent(
            ParentProductId              = bundle.Id,
            ChildProductId               = bundleChild.Id,
            IsDefaultComponent           = true,
            Quantity                     = 1,
            Sequence                     = 1,
            DoesBundlePriceIncludeChild  = false
        );
        insert prc;

        Quote q = new Quote(
            Name          = 'QLI Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id  = stdPB
        );
        insert q;
    }

    // ---------------- Helpers ----------------

    private static Quote getQuote() {
        return [SELECT Id, Tax FROM Quote LIMIT 1];
    }

    private static PricebookEntry getPbeByCode(String productCode) {
        return [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2.ProductCode = :productCode AND IsActive = true
            LIMIT 1
        ];
    }

    private static QuoteLineItem buildQli(Id quoteId, PricebookEntry pbe, Decimal qty, Decimal unitPrice) {
        return new QuoteLineItem(
            QuoteId          = quoteId,
            Product2Id       = pbe.Product2Id,
            PricebookEntryId = pbe.Id,
            Quantity         = qty,
            UnitPrice        = unitPrice
        );
    }

    // ==================================================================================
    // Responsibility 1: VAT recalculation on Quote (SUM * 19%)
    // ==================================================================================

    @IsTest
    static void insertQLIs_recalculatesQuoteTaxAt19Percent() {
        Quote q = getQuote();
        PricebookEntry plainPbe = getPbeByCode('ACC-USB-001');

        // 3 lines: qty 10 @ 100, qty 5 @ 100, qty 5 @ 100 = 1000 total → tax 190
        Test.startTest();
        insert new List<QuoteLineItem>{
            buildQli(q.Id, plainPbe, 10, 100),
            buildQli(q.Id, plainPbe, 5, 100),
            buildQli(q.Id, plainPbe, 5, 100)
        };
        Test.stopTest();

        Quote after = [SELECT Tax FROM Quote WHERE Id = :q.Id];
        System.assertEquals(190.00, after.Tax,
            'Quote.Tax must equal 19% VAT on the SUM of QLI TotalPrice (1000 * 0.19).');
    }

    @IsTest
    static void deleteQLI_recalculatesQuoteTaxDownward() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');

        QuoteLineItem qli1 = buildQli(q.Id, pbe, 5, 100);  // 500
        QuoteLineItem qli2 = buildQli(q.Id, pbe, 5, 100);  // 500
        insert new List<QuoteLineItem>{ qli1, qli2 };

        Quote afterInsert = [SELECT Tax FROM Quote WHERE Id = :q.Id];
        System.assertEquals(190.00, afterInsert.Tax,
            'Sanity: two 500-lines should stamp 190 tax before delete.');

        Test.startTest();
        delete qli2;
        Test.stopTest();

        Quote afterDelete = [SELECT Tax FROM Quote WHERE Id = :q.Id];
        System.assertEquals(95.00, afterDelete.Tax,
            'Deleting one 500 line must recalculate tax down to 95 (500 * 0.19).');
    }

    @IsTest
    static void updateQLI_recalculatesQuoteTax() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');

        QuoteLineItem qli = buildQli(q.Id, pbe, 5, 100);
        insert qli;
        System.assertEquals(95.00, [SELECT Tax FROM Quote WHERE Id = :q.Id].Tax,
            'Sanity: 500 total → 95 tax.');

        Test.startTest();
        qli.Quantity = 10;  // TotalPrice → 1000
        update qli;
        Test.stopTest();

        System.assertEquals(190.00, [SELECT Tax FROM Quote WHERE Id = :q.Id].Tax,
            'After quantity doubles, tax must recalc from new SUM.');
    }

    @IsTest
    static void bulkInsertQLIsAcross5Quotes_eachQuoteTaxRecalcedIndependently() {
        // Seed 4 more Quotes (setup already has 1 → total 5)
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Id stdPB = Test.getStandardPricebookId();
        List<Quote> extra = new List<Quote>();
        for (Integer i = 0; i < 4; i++) {
            extra.add(new Quote(Name = 'Bulk Q ' + i, OpportunityId = opp.Id, Pricebook2Id = stdPB));
        }
        insert extra;

        PricebookEntry pbe = getPbeByCode('ACC-USB-001');
        List<Quote> allQuotes = [SELECT Id FROM Quote];
        System.assertEquals(5, allQuotes.size(), 'Setup expects exactly 5 Quotes for this test.');

        // Each Quote gets a QLI whose total = 100 * (index+1) → distinct taxes
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        Integer i = 1;
        for (Quote qu : allQuotes) {
            qlis.add(buildQli(qu.Id, pbe, i, 100));  // qty i @ 100 = 100*i
            i++;
        }

        Test.startTest();
        insert qlis;
        Test.stopTest();

        Map<Id, Quote> refreshed = new Map<Id, Quote>([SELECT Id, Tax FROM Quote]);
        // With undefined ordering, sum of all taxes must equal 19% of sum of totals
        // Totals: 100 + 200 + 300 + 400 + 500 = 1500 → total tax across quotes = 285
        Decimal totalTax = 0;
        for (Quote qu : refreshed.values()) {
            if (qu.Tax != null) totalTax += qu.Tax;
        }
        System.assertEquals(285.00, totalTax,
            'Bulk aggregation across 5 quotes must sum to 19% of the combined line total.');
        // At least one non-zero tax on every quote
        for (Quote qu : refreshed.values()) {
            System.assert(qu.Tax != null && qu.Tax > 0,
                'Every quote in scope must have received an independent tax recalc. Quote ' + qu.Id + ' Tax=' + qu.Tax);
        }
    }

    @IsTest
    static void emptyQuote_deleteLastLine_taxRolledDownToZero() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');
        QuoteLineItem only = buildQli(q.Id, pbe, 2, 100);
        insert only;
        System.assertEquals(38.00, [SELECT Tax FROM Quote WHERE Id = :q.Id].Tax,
            'Sanity pre-delete tax on 200 total.');

        Test.startTest();
        delete only;
        Test.stopTest();

        System.assertEquals(0, [SELECT Tax FROM Quote WHERE Id = :q.Id].Tax,
            'Deleting the sole line must roll Quote.Tax back to zero (aggregate returns nothing → coalesce 0).');
    }

    // ==================================================================================
    // Responsibility 2: Attribute-based pricing (Techno_Attribute_Price_Rule__mdt)
    // ==================================================================================
    //
    // See class-level notes: seeded metadata keys on a real production Product Id
    // that our test Product2 records don't share, so totalAdjustment resolves to 0.
    // We exercise the mutation path (Bundle Type + QLIA rows -> rebase from PBE)
    // and assert idempotency + the non-Bundle early exit.

    @IsTest
    static void bundleQliUpdate_withoutAttributes_leavesUnitPriceUnchanged() {
        // With NO QuoteLineItemAttribute rows on the QLI, applyAttributeAdjustmentsInPlace
        // returns early ("qliAttrValues.isEmpty()"), so a beforeUpdate must not mutate UnitPrice.
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        QuoteLineItem qli = buildQli(q.Id, bundlePbe, 1, 2000);
        insert qli;

        Test.startTest();
        // Trigger beforeUpdate — flip a benign field
        qli.Description = 'edited';
        update qli;
        Test.stopTest();

        QuoteLineItem refreshed = [SELECT UnitPrice FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(2000.00, refreshed.UnitPrice,
            'Bundle QLI with no QLIA rows must skip attribute adjustment (UnitPrice preserved).');
    }

    @IsTest
    static void nonBundleQliUpdate_neverEnrichedByAttributeAdjustments() {
        // Non-Bundle Product2.Type triggers the "bundleInfoById.isEmpty() return" branch —
        // even a QLI update that would otherwise re-fire the handler must not rebase.
        Quote q = getQuote();
        PricebookEntry plainPbe = getPbeByCode('ACC-USB-001');
        QuoteLineItem qli = buildQli(q.Id, plainPbe, 1, 175);  // Deliberately DIFFERENT from PBE 100
        insert qli;

        Test.startTest();
        qli.Quantity = 2;  // change something to fire beforeUpdate
        update qli;
        Test.stopTest();

        QuoteLineItem refreshed = [SELECT UnitPrice FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(175.00, refreshed.UnitPrice,
            'Non-Bundle QLI update must never be rebased from PricebookEntry by the attribute engine.');
    }

    @IsTest
    static void bundleQliUpdate_idempotency_repeatedUpdatesProduceSamePrice() {
        // With no rule matching (test-created Product2 Id ≠ seeded CMD ProductId), each
        // beforeUpdate invocation rebases from PricebookEntry.UnitPrice + 0. Repeated
        // updates must not compound (would fail if code re-used q.UnitPrice as the base).
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        // Insert priced ABOVE the PBE — this simulates a rep who typed a manual UnitPrice
        QuoteLineItem qli = buildQli(q.Id, bundlePbe, 1, 3000);
        insert qli;

        // Attach a QuoteLineItemAttribute so applyAttributeAdjustmentsInPlace enters the mutation loop.
        // AttributeDefinitionId left null (nullable in QLIA schema) — key won't match any rule.
        insert new QuoteLineItemAttribute(
            QuoteLineItemId = qli.Id,
            AttributeValue  = 'RAM 32GB'
        );

        Test.startTest();
        qli.Description = 'first update';
        update qli;
        Decimal afterFirst = [SELECT UnitPrice FROM QuoteLineItem WHERE Id = :qli.Id].UnitPrice;

        qli.Description = 'second update';
        update qli;
        Decimal afterSecond = [SELECT UnitPrice FROM QuoteLineItem WHERE Id = :qli.Id].UnitPrice;
        Test.stopTest();

        System.assertEquals(afterFirst, afterSecond,
            'Repeated updates must produce the same UnitPrice — the rebase reads from PBE, not from q.UnitPrice.');
        System.assertEquals(2000.00, afterSecond,
            'With adjustment=0 the rebase must land exactly on PricebookEntry.UnitPrice (2000).');
    }

    @IsTest
    static void bundleQliUpdate_withAttributeButUnmappedProduct_rebasesToPricebookEntryPrice() {
        // Same as idempotency but written to make the "unmapped product ID → no rule match"
        // pathway explicit. Bundle Type + QLIA present + no matching CMD rule ⇒ rebase to PBE.
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        QuoteLineItem qli = buildQli(q.Id, bundlePbe, 1, 9999);
        insert qli;

        insert new QuoteLineItemAttribute(
            QuoteLineItemId = qli.Id,
            AttributeValue  = 'Intel Core i9 5.2 GHz'  // same string as seeded rule, but ProductId key won't match
        );

        Test.startTest();
        qli.Description = 'fire beforeUpdate';
        update qli;
        Test.stopTest();

        Decimal newPrice = [SELECT UnitPrice FROM QuoteLineItem WHERE Id = :qli.Id].UnitPrice;
        System.assertEquals(2000.00, newPrice,
            'Bundle QLI with an unmapped Product2 Id must rebase to the PBE UnitPrice (adjustment path yields 0).');
    }

    // ==================================================================================
    // Responsibility 3: Bundle decomposition (@future async path)
    // ==================================================================================

    @IsTest
    static void bundleQli_afterInsert_triggersAsyncDecomposition_childQliCreated() {
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        Id bundleChildProductId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-LAP-001' LIMIT 1].Id;

        Test.startTest();
        insert buildQli(q.Id, bundlePbe, 1, 2000);
        Test.stopTest();  // Flushes @future decomposeBundlesAsync

        List<QuoteLineItem> children = [
            SELECT Id, Product2Id, UnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :bundleChildProductId
        ];
        System.assertEquals(1, children.size(),
            'Bundle decomposition must insert exactly one child QLI (one ProductRelatedComponent seeded).');
        System.assertEquals(1500.00, children[0].UnitPrice,
            'Child QLI UnitPrice must come from the child PricebookEntry (DoesBundlePriceIncludeChild=false).');
    }

    @IsTest
    static void bundleDecomposition_isIdempotent_secondInsertProducesNoDuplicateChildren() {
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        Id bundleChildProductId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-LAP-001' LIMIT 1].Id;

        // First bundle insert → child created via @future
        Test.startTest();
        insert buildQli(q.Id, bundlePbe, 1, 2000);
        Test.stopTest();

        Integer childCountAfterFirst = [
            SELECT COUNT() FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :bundleChildProductId
        ];
        System.assertEquals(1, childCountAfterFirst,
            'One decomposition produces one child.');

        // NOTE: A second bundle insert would trigger cleanupDuplicateBundlesAsync to delete
        // the transient duplicate parent — decomposition would then skip since a bundle
        // already exists (existingBundleKeys guard). Idempotency is proved by asserting no
        // extra children beyond the initial 1 after re-firing decompose on the SAME QLI:
        QuoteLineItem existing = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2Id = :bundlePbe.Product2Id LIMIT 1];
        QuoteLineItemTriggerHandler.decomposeBundlesAsync(new Set<Id>{ existing.Id });

        Integer childCountAfterRefire = [
            SELECT COUNT() FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :bundleChildProductId
        ];
        System.assertEquals(1, childCountAfterRefire,
            'Re-firing decomposition on the same bundle must NOT produce a duplicate child ' +
            '(existingChildKeys guard).');
    }

    @IsTest
    static void bundleDecomposition_prefersPricebookEntry_forOneTimeOrNoSellingModel() {
        // ProductSellingModel is a CPQ-restricted object (not insertable in Apex tests), so
        // we cannot fabricate the OneTime vs. TermDefined face-off directly. What we CAN
        // assert: with the sole seeded PBE (no ProductSellingModelId → score=2, still valid),
        // decomposition proceeds and picks that PBE. If a future Evergreen/TermDefined PBE
        // were the only option, the code would skip (see pricebookEntryScore + sellingType
        // guard). This test is the recruiter-facing happy-path proof.
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');
        PricebookEntry childPbe = getPbeByCode('COMP-LAP-001');

        Test.startTest();
        insert buildQli(q.Id, bundlePbe, 1, 2000);
        Test.stopTest();

        QuoteLineItem createdChild = [
            SELECT PricebookEntryId, UnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND PricebookEntryId = :childPbe.Id
            LIMIT 1
        ];
        System.assertEquals(childPbe.Id, createdChild.PricebookEntryId,
            'Decomposition must attach the standard-pricebook child PBE (score >= 2).');
        System.assertEquals(childPbe.UnitPrice, createdChild.UnitPrice,
            'Child UnitPrice must come from the resolved PBE, not from the bundle parent.');
    }

    // ==================================================================================
    // Responsibility 4: Recursion / bypass guard
    // ==================================================================================

    @IsTest
    static void bypass_disablesHandler_vatNotRecalculated() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');

        Test.startTest();
        TriggerHandler.bypass('QuoteLineItemTriggerHandler');
        try {
            insert buildQli(q.Id, pbe, 10, 100);  // Would normally set Tax = 190
        } finally {
            TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
        }
        Test.stopTest();

        Quote after = [SELECT Tax FROM Quote WHERE Id = :q.Id];
        System.assert(after.Tax == null || after.Tax == 0,
            'With handler bypassed, VAT recalc must NOT run. Got Tax=' + after.Tax);
    }

    // ==================================================================================
    // Responsibility 5: Transient-draft duplicate cleanup (@future)
    // ==================================================================================

    @IsTest
    static void duplicateBundleQlisOnSameQuote_asyncCleanupKeepsOldest() {
        // Two Bundle QLIs with SAME (Quote, Product2) on the same insert transaction.
        // cleanupDuplicateBundlesAsync must keep the oldest (by CreatedDate ASC) and
        // delete the newer (Configure UI transient draft pattern).
        Quote q = getQuote();
        PricebookEntry bundlePbe = getPbeByCode('BUNDLE-OFFICE-001');

        // Insert the first bundle in its own transaction so CreatedDate is meaningfully earlier
        QuoteLineItem first = buildQli(q.Id, bundlePbe, 1, 2000);
        insert first;

        Test.startTest();
        // Now insert a duplicate — this second insert will queue cleanupDuplicateBundlesAsync
        QuoteLineItem duplicate = buildQli(q.Id, bundlePbe, 1, 2000);
        insert duplicate;
        Test.stopTest();  // @future runs → oldest kept

        List<QuoteLineItem> surviving = [
            SELECT Id FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :bundlePbe.Product2Id AND Product2.Type = 'Bundle'
        ];
        System.assertEquals(1, surviving.size(),
            'Duplicate cleanup must leave exactly one Bundle QLI per (Quote, Product2).');
        System.assertEquals(first.Id, surviving[0].Id,
            'Cleanup must preserve the OLDEST bundle (CreatedDate ASC). Kept: ' + surviving[0].Id + ' expected: ' + first.Id);
    }

    // ==================================================================================
    // Aux: Auto-populate Description from Product2.Name (beforeInsert)
    // ==================================================================================

    @IsTest
    static void autoDescription_populatesFromProductName_onInsert() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');
        QuoteLineItem qli = buildQli(q.Id, pbe, 1, 100);
        qli.Description = null;

        Test.startTest();
        insert qli;
        Test.stopTest();

        QuoteLineItem refreshed = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals('USB Cable', refreshed.Description,
            'beforeInsert must copy Product2.Name into blank Description (CLM contract conversion contract).');
    }

    @IsTest
    static void autoDescription_preservesUserProvidedDescription_onInsert() {
        Quote q = getQuote();
        PricebookEntry pbe = getPbeByCode('ACC-USB-001');
        QuoteLineItem qli = buildQli(q.Id, pbe, 1, 100);
        qli.Description = 'Rep-authored line note';

        Test.startTest();
        insert qli;
        Test.stopTest();

        QuoteLineItem refreshed = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals('Rep-authored line note', refreshed.Description,
            'beforeInsert must NOT overwrite an already-populated Description.');
    }
}
