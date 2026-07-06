/**
 * Unit tests for BundleDecompositionAction.
 *
 * Covers the Bundle-QLI decomposition invocable action:
 *   - Default children (IsDefaultComponent=true) get inserted; non-defaults are skipped
 *   - Included-in-bundle-price children get UnitPrice=0; add-on children take PBE.UnitPrice
 *   - Idempotency: second run on the same quote does not duplicate children
 *   - PricebookEntry scoring: OneTime (3) beats null-SellingModel (2); Evergreen/TermDefined
 *     PBEs are skipped (score 0)
 *   - Guard branches: null quoteId, unknown quoteId, empty request list, bundle with no PRCs
 *   - Multiple Bundle QLIs on a single Quote each get decomposed
 *   - Response.statusMessage carries a human-readable summary
 *
 * TS-TEST-015: adds one @TestVisible to BundleDecompositionAction.pricebookEntryScore so we
 * can score PBE candidates in memory without needing the Revenue Cloud multi-PBE-per-product
 * feature to be enabled in the org running this test.
 *
 * PricebookEntry note: on stock Sales Cloud a single (Pricebook2Id, Product2Id) tuple has
 * exactly one PBE. Revenue Cloud allows multiple PBEs per tuple when they differ by
 * ProductSellingModelId. Rather than assume that feature is on, the scoring tests build
 * in-memory PBE records via JSON.deserialize (no insert), which is sufficient to exercise
 * pricebookEntryScore's pure logic.
 */
@IsTest
private class BundleDecompositionActionTest {

    private static final String BUNDLE_NAME    = 'Test Bundle Package';
    private static final String COMP_A_NAME    = 'Component A';
    private static final String COMP_B_NAME    = 'Component B';
    private static final String COMP_C_NAME    = 'Component C - Add-on';

    // ---------- @TestSetup: Account/Opportunity/Quote + Products + PBEs + PRCs + Bundle QLI ----------

    @TestSetup
    static void seed() {
        Account a = TestDataFactory.newAccount('BundleTest DE GmbH');

        Opportunity opp = new Opportunity(
            AccountId = a.Id,
            Name      = 'Bundle Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Bundle parent + three children
        Product2 bundle = new Product2(Name = BUNDLE_NAME, IsActive = true, Type = 'Bundle');
        Product2 compA  = new Product2(Name = COMP_A_NAME, IsActive = true);
        Product2 compB  = new Product2(Name = COMP_B_NAME, IsActive = true);
        Product2 compC  = new Product2(Name = COMP_C_NAME, IsActive = true);
        insert new List<Product2>{ bundle, compA, compB, compC };

        Id stdPB = Test.getStandardPricebookId();
        PricebookEntry pbeBundle = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = bundle.Id,
            UnitPrice = 2000, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbeA = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = compA.Id,
            UnitPrice = 300, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbeB = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = compB.Id,
            UnitPrice = 500, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbeC = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = compC.Id,
            UnitPrice = 150, IsActive = true, UseStandardPrice = false
        );
        insert new List<PricebookEntry>{ pbeBundle, pbeA, pbeB, pbeC };

        // Bundle → children mapping.
        // A + B are defaults (auto-added); C is not (opt-in add-on).
        ProductRelatedComponent prcA = new ProductRelatedComponent(
            ParentProductId = bundle.Id, ChildProductId = compA.Id,
            IsDefaultComponent = true, Sequence = 10,
            DoesBundlePriceIncludeChild = true, Quantity = 1
        );
        ProductRelatedComponent prcB = new ProductRelatedComponent(
            ParentProductId = bundle.Id, ChildProductId = compB.Id,
            IsDefaultComponent = true, Sequence = 20,
            DoesBundlePriceIncludeChild = true, Quantity = 1
        );
        ProductRelatedComponent prcC = new ProductRelatedComponent(
            ParentProductId = bundle.Id, ChildProductId = compC.Id,
            IsDefaultComponent = false, Sequence = 30,
            DoesBundlePriceIncludeChild = false, Quantity = 1
        );
        insert new List<ProductRelatedComponent>{ prcA, prcB, prcC };

        Quote q = new Quote(
            Name         = 'Bundle Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPB
        );
        insert q;

        // The parent Bundle QLI on the quote — this is what decomposition targets.
        QuoteLineItem bundleQli = new QuoteLineItem(
            QuoteId          = q.Id,
            Product2Id       = bundle.Id,
            PricebookEntryId = pbeBundle.Id,
            Quantity         = 1,
            UnitPrice        = 2000
        );
        insert bundleQli;
    }

    // ---------- Helpers ----------

    private static Id getSeededQuoteId() {
        return [SELECT Id FROM Quote LIMIT 1].Id;
    }

    private static Id getBundleProductId() {
        return [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1].Id;
    }

    private static Id getComponentProductId(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
    }

    private static BundleDecompositionAction.Request buildRequest(Id quoteId) {
        BundleDecompositionAction.Request r = new BundleDecompositionAction.Request();
        r.quoteId = quoteId;
        return r;
    }

    private static Integer childQliCount(Id quoteId) {
        return [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId AND Product2.Type != 'Bundle'];
    }

    /**
     * Build an in-memory PricebookEntry with an optional nested ProductSellingModel of the given
     * SellingModelType. Used only by the scoring tests — never inserted.
     */
    private static PricebookEntry buildScoringPbe(String sellingModelType, Boolean hasModelId) {
        // JSON-deserialize is the only way to attach a nested SObject to a parent without DML.
        String modelBlock = (sellingModelType == null)
            ? 'null'
            : '{"attributes":{"type":"ProductSellingModel"},"SellingModelType":"' + sellingModelType + '"}';
        String modelIdField = hasModelId
            ? ',"ProductSellingModelId":"0jP000000000001AAA"'
            : '';
        String json =
            '{"attributes":{"type":"PricebookEntry"},"UnitPrice":100,"IsActive":true'
            + modelIdField
            + ',"ProductSellingModel":' + modelBlock + '}';
        return (PricebookEntry) System.JSON.deserialize(json, Schema.PricebookEntry.class);
    }

    // ---------- Tests ----------

    @IsTest
    static void run_bundleQliOnQuote_insertsDefaultChildQlis() {
        Id quoteId = getSeededQuoteId();
        Id compAId = getComponentProductId(COMP_A_NAME);
        Id compBId = getComponentProductId(COMP_B_NAME);
        Id compCId = getComponentProductId(COMP_C_NAME);

        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request should produce one result');
        System.assertEquals(2, results[0].childrenCreated,
            'Only IsDefaultComponent=true children (A + B) should be inserted; C is opt-in');

        Map<Id, QuoteLineItem> childrenByProduct = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : [SELECT Id, Product2Id, UnitPrice, Quantity FROM QuoteLineItem
                                WHERE QuoteId = :quoteId AND Product2.Type != 'Bundle']) {
            childrenByProduct.put(q.Product2Id, q);
        }
        System.assertEquals(2, childrenByProduct.size(), 'Exactly 2 child QLIs expected on the quote');
        System.assert(childrenByProduct.containsKey(compAId), 'Component A must be present');
        System.assert(childrenByProduct.containsKey(compBId), 'Component B must be present');
        System.assert(!childrenByProduct.containsKey(compCId),
            'Component C (IsDefaultComponent=false) must NOT be auto-inserted');
    }

    @IsTest
    static void run_includedChildren_unitPriceIsZero() {
        Id quoteId = getSeededQuoteId();

        Test.startTest();
        BundleDecompositionAction.decompose(new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) });
        Test.stopTest();

        List<QuoteLineItem> children = [
            SELECT Id, Product2.Name, UnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND Product2.Type != 'Bundle'
        ];
        System.assertEquals(2, children.size(), 'Two included children expected');
        for (QuoteLineItem c : children) {
            System.assertEquals(0, c.UnitPrice,
                'DoesBundlePriceIncludeChild=true must produce UnitPrice=0. Product: ' + c.Product2.Name);
        }
    }

    @IsTest
    static void run_isIdempotent_secondRunDoesNotDuplicate() {
        Id quoteId = getSeededQuoteId();

        Test.startTest();
        BundleDecompositionAction.decompose(new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) });
        Integer afterFirst = childQliCount(quoteId);

        // Second invocation — QuoteId|Product2Id dedupe key should filter out the already-present rows.
        List<BundleDecompositionAction.Result> secondResults = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) }
        );
        Test.stopTest();

        Integer afterSecond = childQliCount(quoteId);
        System.assertEquals(2, afterFirst, 'First run should insert 2 children');
        System.assertEquals(2, afterSecond, 'Second run must NOT duplicate children');
        System.assertEquals(0, secondResults[0].childrenCreated,
            'Second run must report 0 new children created');
        System.assert(secondResults[0].statusMessage != null
            && secondResults[0].statusMessage.contains('already on the quote'),
            'Status message should indicate nothing to add. Got: ' + secondResults[0].statusMessage);
    }

    @IsTest
    static void run_pricebookEntryScoring_prefersOneTime_overNoSellingModel() {
        // Direct exercise of the scoring rule via @TestVisible helper.
        PricebookEntry oneTimePbe   = buildScoringPbe('OneTime', true);
        PricebookEntry nullModelPbe = buildScoringPbe(null,      false);

        Test.startTest();
        Integer oneTimeScore   = BundleDecompositionAction.pricebookEntryScore(oneTimePbe);
        Integer nullModelScore = BundleDecompositionAction.pricebookEntryScore(nullModelPbe);
        Test.stopTest();

        System.assertEquals(3, oneTimeScore,   'OneTime SellingModelType must score 3');
        System.assertEquals(2, nullModelScore, 'Null ProductSellingModelId must score 2');
        System.assert(oneTimeScore > nullModelScore,
            'OneTime PBE must be preferred over null-selling-model PBE');
    }

    @IsTest
    static void run_pricebookEntryScoring_skipsSubscriptionModels_evergreen_and_termDefined() {
        PricebookEntry evergreenPbe    = buildScoringPbe('Evergreen',    true);
        PricebookEntry termDefinedPbe  = buildScoringPbe('TermDefined',  true);
        PricebookEntry oneTimePbe      = buildScoringPbe('OneTime',      true);

        Test.startTest();
        Integer evergreenScore   = BundleDecompositionAction.pricebookEntryScore(evergreenPbe);
        Integer termDefinedScore = BundleDecompositionAction.pricebookEntryScore(termDefinedPbe);
        Integer oneTimeScore     = BundleDecompositionAction.pricebookEntryScore(oneTimePbe);
        Integer nullScore        = BundleDecompositionAction.pricebookEntryScore(null);
        Test.stopTest();

        System.assertEquals(0, evergreenScore,   'Evergreen subscription model must score 0 (skipped)');
        System.assertEquals(0, termDefinedScore, 'TermDefined subscription model must score 0 (skipped)');
        System.assertEquals(3, oneTimeScore,     'OneTime should still score 3 in the same comparison');
        System.assertEquals(0, nullScore,        'Null PBE must score 0 defensively');
    }

    @IsTest
    static void run_noProductRelatedComponents_returnsGracefully() {
        // Remove every PRC so the bundle has no default children to decompose.
        delete [SELECT Id FROM ProductRelatedComponent];
        Id quoteId = getSeededQuoteId();

        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request must still produce one result');
        System.assertEquals(0, results[0].childrenCreated, 'No children should be inserted');
        System.assert(results[0].statusMessage != null,
            'Status message should not be null');
        System.assert(results[0].statusMessage.contains('already on the quote')
                   || results[0].statusMessage.contains('nothing to add'),
            'Status message should indicate no decomposable rows. Got: ' + results[0].statusMessage);
        System.assertEquals(0, childQliCount(quoteId),
            'Zero non-bundle QLIs must be present');
    }

    @IsTest
    static void run_multipleBundleQlisOnQuote_decomposesEach() {
        Id quoteId = getSeededQuoteId();
        Id stdPB   = Test.getStandardPricebookId();

        // Second bundle with two distinct default children (X + Y).
        Product2 bundle2 = new Product2(Name = 'Test Bundle Package 2', IsActive = true, Type = 'Bundle');
        Product2 compX   = new Product2(Name = 'Component X', IsActive = true);
        Product2 compY   = new Product2(Name = 'Component Y', IsActive = true);
        insert new List<Product2>{ bundle2, compX, compY };

        PricebookEntry pbeBundle2 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = bundle2.Id,
            UnitPrice = 4000, IsActive = true, UseStandardPrice = false);
        PricebookEntry pbeX = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = compX.Id,
            UnitPrice = 250, IsActive = true, UseStandardPrice = false);
        PricebookEntry pbeY = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = compY.Id,
            UnitPrice = 750, IsActive = true, UseStandardPrice = false);
        insert new List<PricebookEntry>{ pbeBundle2, pbeX, pbeY };

        insert new List<ProductRelatedComponent>{
            new ProductRelatedComponent(
                ParentProductId = bundle2.Id, ChildProductId = compX.Id,
                IsDefaultComponent = true, Sequence = 10,
                DoesBundlePriceIncludeChild = false, Quantity = 1
            ),
            new ProductRelatedComponent(
                ParentProductId = bundle2.Id, ChildProductId = compY.Id,
                IsDefaultComponent = true, Sequence = 20,
                DoesBundlePriceIncludeChild = false, Quantity = 2
            )
        };

        // Second bundle QLI on the same quote.
        insert new QuoteLineItem(
            QuoteId          = quoteId,
            Product2Id       = bundle2.Id,
            PricebookEntryId = pbeBundle2.Id,
            Quantity         = 1,
            UnitPrice        = 4000
        );

        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) }
        );
        Test.stopTest();

        System.assertEquals(4, results[0].childrenCreated,
            'Two bundles × two defaults each = 4 child QLIs');
        System.assertEquals(4, childQliCount(quoteId),
            'All four children should be persisted on the quote');

        // Add-on children (DoesBundlePriceIncludeChild=false) take PBE.UnitPrice, not $0.
        List<QuoteLineItem> xy = [
            SELECT Product2.Name, UnitPrice, Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND (Product2.Name = 'Component X' OR Product2.Name = 'Component Y')
        ];
        System.assertEquals(2, xy.size(), 'Expected two add-on children (X + Y)');
        for (QuoteLineItem c : xy) {
            System.assert(c.UnitPrice > 0,
                'Add-on child ' + c.Product2.Name + ' should use PBE price, not 0');
        }
    }

    @IsTest
    static void run_nullQuoteId_returnsErrorStatusMessage() {
        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(null) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request → one result even with null quoteId');
        System.assertEquals(0, results[0].childrenCreated,
            'No children should be created for a null-quoteId request');
        System.assert(results[0].statusMessage != null
            && results[0].statusMessage.contains('No Quote Id'),
            'Status message must call out the null Quote Id. Got: ' + results[0].statusMessage);
    }

    @IsTest
    static void run_unknownQuoteId_returnsSafely() {
        // A well-formed Quote Id that no longer resolves — delete-then-reference.
        Id ghost = getSeededQuoteId();
        // First delete the QLIs on it (child, parent order matters), then the Quote itself.
        delete [SELECT Id FROM QuoteLineItem WHERE QuoteId = :ghost];
        delete new Quote(Id = ghost);

        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(ghost) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Guard should still produce one Result');
        System.assertEquals(0, results[0].childrenCreated,
            'No child QLIs should be created for an unknown Quote Id');
        System.assert(results[0].statusMessage != null
            && results[0].statusMessage.contains('No Bundle line items'),
            'Status should say no bundle QLIs found on this quote. Got: ' + results[0].statusMessage);
    }

    @IsTest
    static void run_emptyRequestList_returnsEmptyResponses() {
        Test.startTest();
        List<BundleDecompositionAction.Result> resNull  = BundleDecompositionAction.decompose(null);
        List<BundleDecompositionAction.Result> resEmpty = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>()
        );
        Test.stopTest();

        System.assertEquals(0, resNull.size(),  'null request list must return an empty results list');
        System.assertEquals(0, resEmpty.size(), 'empty request list must return an empty results list');
        System.assertEquals(0, Limits.getQueries(),
            'No SOQL should have been consumed for null/empty requests');
    }

    @IsTest
    static void run_response_statusMessage_describesResults() {
        Id quoteId = getSeededQuoteId();

        Test.startTest();
        List<BundleDecompositionAction.Result> results = BundleDecompositionAction.decompose(
            new List<BundleDecompositionAction.Request>{ buildRequest(quoteId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(2, results[0].childrenCreated,
            'childrenCreated must reflect the actual insert count');
        System.assert(results[0].statusMessage != null,
            'statusMessage must not be null');
        System.assert(results[0].statusMessage.contains('2'),
            'statusMessage must include the number of components added. Got: ' + results[0].statusMessage);
        System.assert(results[0].statusMessage.contains('component'),
            'statusMessage should describe the operation with the word "component". Got: '
            + results[0].statusMessage);
    }
}
