/**
 * Trigger handler for QuoteLineItem.
 *
 * Responsibilities:
 *   1. Auto-populate Description from Product2.Name (for CLM contract conversion).
 *   2. Recalculate Quote.Tax = SUM(line VAT 19%) on every QLI insert/update/delete/undelete.
 *   3. Apply attribute-based price adjustments on Bundle QLIs in beforeUpdate, sourced from
 *      Techno_Attribute_Price_Rule__mdt custom metadata (see applyAttributeAdjustmentsInPlace
 *      docstring for why custom metadata instead of native AttributeBasedAdjustment).
 *   4. Auto-decompose Bundle parents into child QLIs ASYNCHRONOUSLY after the parent QLI is
 *      updated (i.e. after Configure UI's Save & Exit transaction commits). Decomposing
 *      synchronously inside the trigger would expose the orphan children (their
 *      ParentQuoteLineItemId is platform-managed and not writeable from Apex) to Configure
 *      UI's commit-time validation, producing the misleading "Required fields missing:
 *      [Price Book Entry]" + "Your quote was not updated" red toasts. Running async via
 *      @future moves the insert outside the LWC's validation window — toasts disappear.
 *   5. Async cleanup of duplicate Bundle QLIs that Configure UI commits as transient drafts
 *      during Save & Exit. The OLDEST bundle of each (Quote, Product2) pair is the user's
 *      intentional add and is preserved; newer duplicates are deleted.
 *
 * Extends Kevin O'Hara TriggerHandler framework.
 */
public with sharing class QuoteLineItemTriggerHandler extends TriggerHandler {

    private static final Decimal VAT_RATE = 0.19;
    private static Boolean isBundleDecompositionRunning = false;

    @TestVisible
    private List<QuoteLineItem> records {
        get { return (List<QuoteLineItem>) Trigger.new; }
    }

    @TestVisible
    private List<QuoteLineItem> oldRecords {
        get { return (List<QuoteLineItem>) Trigger.old; }
    }

    protected override void beforeInsert() {
        autoPopulateDescription();
        enforcePOSIndustryEligibility(records);
    }

    protected override void beforeUpdate() {
        autoPopulateDescription();
        applyAttributeAdjustmentsInPlace(records);
        enforcePOSIndustryEligibility(records);
    }

    protected override void afterInsert() {
        // Bundle decomposition is NOT done here — see afterUpdate. Inserting children at bundle-add
        // time would cause orphan children (ParentQuoteLineItemId is platform-managed and not
        // writeable from Apex) to be visible to Configure UI's commit-time validation when the
        // user later does Save & Exit, producing the misleading "Required fields missing:
        // [Price Book Entry]" + "Your quote was not updated" toasts.
        Set<Id> insertedIds = new Set<Id>();
        for (QuoteLineItem q : records) if (q.Id != null) insertedIds.add(q.Id);
        if (!insertedIds.isEmpty() && !System.isFuture() && !System.isBatch() && !System.isQueueable()) {
            cleanupDuplicateBundlesAsync(insertedIds);
        }
        recalculateQuoteTax(quoteIdsFromRecords(records));
    }

    protected override void afterUpdate() {
        // Queue async decomposition for any updated Bundle QLIs. Running async (after Configure
        // UI's Save & Exit transaction commits) means the orphan children we insert never appear
        // inside the LWC's commit-time validation window — no toast. Idempotent dedupe inside
        // autoDecomposeBundles ensures repeat updates (Reprice All, attribute re-edits) don't
        // duplicate children.
        Set<Id> updatedIds = new Set<Id>();
        for (QuoteLineItem q : records) if (q.Id != null) updatedIds.add(q.Id);
        if (!updatedIds.isEmpty() && !System.isFuture() && !System.isBatch() && !System.isQueueable()) {
            decomposeBundlesAsync(updatedIds);
        }
        recalculateQuoteTax(quoteIdsFromRecords(records));
    }

    protected override void afterDelete() {
        recalculateQuoteTax(quoteIdsFromRecords(oldRecords));
    }

    protected override void afterUndelete() {
        recalculateQuoteTax(quoteIdsFromRecords(records));
    }

    private static Set<Id> quoteIdsFromRecords(List<QuoteLineItem> qlis) {
        Set<Id> result = new Set<Id>();
        if (qlis == null) return result;
        for (QuoteLineItem q : qlis) {
            if (q.QuoteId != null) result.add(q.QuoteId);
        }
        return result;
    }

    private void autoPopulateDescription() {
        Set<Id> needProduct = new Set<Id>();
        for (QuoteLineItem q : records) {
            if (String.isBlank(q.Description) && q.Product2Id != null) needProduct.add(q.Product2Id);
        }
        if (needProduct.isEmpty()) return;
        Map<Id, Product2> prodMap = new Map<Id, Product2>([
            SELECT Id, Name FROM Product2 WHERE Id IN :needProduct
        ]);
        for (QuoteLineItem q : records) {
            if (String.isBlank(q.Description) && q.Product2Id != null) {
                Product2 p = prodMap.get(q.Product2Id);
                if (p != null) q.Description = p.Name;
            }
        }
    }

    /**
     * Auto-decompose Bundle parent QLIs into child QLIs at $0.
     *
     * Skips decomposition if a bundle of the same Product2 already exists on the same Quote —
     * that earlier bundle is the user's intentional add. The new insert is virtually always a
     * Configure UI Save & Exit transient draft, which cleanupDuplicateBundlesAsync deletes.
     */
    private static void autoDecomposeBundles(List<QuoteLineItem> newQlis) {
        if (isBundleDecompositionRunning) return;
        if (newQlis == null || newQlis.isEmpty()) return;

        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : newQlis) qliIds.add(q.Id);

        Map<Id, QuoteLineItem> bundleParentQlis = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : [
            SELECT Id, QuoteId, Product2Id, Product2.Type, Product2.BasedOnId,
                   Quantity, PricebookEntryId, PricebookEntry.Pricebook2Id
            FROM QuoteLineItem
            WHERE Id IN :qliIds AND Product2.Type = 'Bundle'
        ]) {
            bundleParentQlis.put(q.Id, q);
        }
        if (bundleParentQlis.isEmpty()) return;

        // Skip duplicates of already-existing bundles on the same Quote (transient draft guard)
        Set<Id> quoteIdsForCheck = new Set<Id>();
        Set<Id> productIdsForCheck = new Set<Id>();
        Set<Id> currentQliIds = bundleParentQlis.keySet();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            quoteIdsForCheck.add(q.QuoteId);
            productIdsForCheck.add(q.Product2Id);
        }
        Set<String> existingBundleKeys = new Set<String>();
        for (QuoteLineItem existing : [
            SELECT QuoteId, Product2Id FROM QuoteLineItem
            WHERE QuoteId IN :quoteIdsForCheck AND Product2Id IN :productIdsForCheck AND Id NOT IN :currentQliIds
        ]) {
            existingBundleKeys.add(existing.QuoteId + '|' + existing.Product2Id);
        }
        Map<Id, QuoteLineItem> filteredBundleParents = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            if (existingBundleKeys.contains(q.QuoteId + '|' + q.Product2Id)) continue;
            filteredBundleParents.put(q.Id, q);
        }
        if (filteredBundleParents.isEmpty()) return;
        bundleParentQlis = filteredBundleParents;

        Set<Id> parentProductIds = new Set<Id>();
        Map<Id, Id> parentClassificationByProduct = new Map<Id, Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            parentProductIds.add(q.Product2Id);
            if (q.Product2.BasedOnId != null) parentClassificationByProduct.put(q.Product2Id, q.Product2.BasedOnId);
        }

        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ChildProduct.BasedOnId, Quantity, IsDefaultComponent
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :parentProductIds AND IsDefaultComponent = true
        ];
        if (components.isEmpty()) return;

        Map<Id, List<ProductRelatedComponent>> childrenByParent = new Map<Id, List<ProductRelatedComponent>>();
        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent c : components) {
            Id parentClassif = parentClassificationByProduct.get(c.ParentProductId);
            Id childClassif = c.ChildProduct != null ? c.ChildProduct.BasedOnId : null;
            if (parentClassif != null && childClassif == parentClassif) continue;
            if (!childrenByParent.containsKey(c.ParentProductId)) childrenByParent.put(c.ParentProductId, new List<ProductRelatedComponent>());
            childrenByParent.get(c.ParentProductId).add(c);
            childProductIds.add(c.ChildProductId);
        }

        // Per-(Quote, ChildProduct) dedupe — covers Configure UI re-fire scenarios
        Set<Id> quoteIdsInScope = new Set<Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) quoteIdsInScope.add(q.QuoteId);
        Set<String> existingChildKeys = new Set<String>();
        for (QuoteLineItem existing : [
            SELECT QuoteId, Product2Id FROM QuoteLineItem
            WHERE QuoteId IN :quoteIdsInScope AND Product2Id IN :childProductIds
        ]) {
            existingChildKeys.add(existing.QuoteId + '|' + existing.Product2Id);
        }

        Set<Id> pricebookIds = new Set<Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            if (q.PricebookEntry != null && q.PricebookEntry.Pricebook2Id != null) pricebookIds.add(q.PricebookEntry.Pricebook2Id);
        }
        Map<String, PricebookEntry> pbeKeyToEntry = new Map<String, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModel.SellingModelType
            FROM PricebookEntry
            WHERE Product2Id IN :childProductIds AND Pricebook2Id IN :pricebookIds AND IsActive = true
        ]) {
            pbeKeyToEntry.put(pbe.Pricebook2Id + '|' + pbe.Product2Id, pbe);
        }

        Set<String> queued = new Set<String>();
        List<QuoteLineItem> childQlis = new List<QuoteLineItem>();
        for (QuoteLineItem parent : bundleParentQlis.values()) {
            List<ProductRelatedComponent> kids = childrenByParent.get(parent.Product2Id);
            if (kids == null) continue;
            Id parentPricebookId = (parent.PricebookEntry != null) ? parent.PricebookEntry.Pricebook2Id : null;
            for (ProductRelatedComponent c : kids) {
                String childKey = parent.QuoteId + '|' + c.ChildProductId;
                if (existingChildKeys.contains(childKey) || queued.contains(childKey)) continue;
                String pbeKey = parentPricebookId + '|' + c.ChildProductId;
                PricebookEntry pbe = pbeKeyToEntry.get(pbeKey);
                if (pbe == null) continue;
                String sellingType = (pbe.ProductSellingModel != null) ? pbe.ProductSellingModel.SellingModelType : null;
                if (sellingType == 'Evergreen' || sellingType == 'TermDefined') continue;

                QuoteLineItem child = new QuoteLineItem();
                child.QuoteId = parent.QuoteId;
                child.Product2Id = c.ChildProductId;
                child.PricebookEntryId = pbe.Id;
                child.Quantity = (c.Quantity != null) ? c.Quantity : 1;
                child.UnitPrice = 0;
                childQlis.add(child);
                queued.add(childKey);
            }
        }

        if (!childQlis.isEmpty()) {
            isBundleDecompositionRunning = true;
            try {
                insert childQlis;
            } finally {
                isBundleDecompositionRunning = false;
            }
        }
    }

    /**
     * Async wrapper that runs autoDecomposeBundles AFTER the inserting/updating transaction
     * commits. By the time this @future fires, Configure UI's Save & Exit session has closed,
     * so the orphan children we insert are never seen by its commit-time validation — eliminating
     * the misleading "Required fields missing: [Price Book Entry]" toast.
     */
    @future
    public static void decomposeBundlesAsync(Set<Id> qliIds) {
        if (qliIds == null || qliIds.isEmpty()) return;
        List<QuoteLineItem> qlis = [
            SELECT Id, QuoteId, Product2Id, Product2.Type, Product2.BasedOnId,
                   Quantity, PricebookEntryId, PricebookEntry.Pricebook2Id
            FROM QuoteLineItem
            WHERE Id IN :qliIds
        ];
        if (qlis.isEmpty()) return;
        autoDecomposeBundles(qlis);
    }

    /**
     * Async cleanup of duplicate Bundle QLIs. Runs after the inserting transaction commits, so
     * Configure UI's Save & Exit session has closed and won't be confused by deletes.
     *
     * For each (Quote, Product2) pair that has 2+ Bundle QLIs, keeps the oldest (the user's
     * intentional add) and deletes the rest (Configure UI transient drafts).
     */
    @future
    public static void cleanupDuplicateBundlesAsync(Set<Id> recentlyInsertedQliIds) {
        if (recentlyInsertedQliIds == null || recentlyInsertedQliIds.isEmpty()) return;

        List<QuoteLineItem> recentBundles = [
            SELECT Id, QuoteId, Product2Id
            FROM QuoteLineItem
            WHERE Id IN :recentlyInsertedQliIds AND Product2.Type = 'Bundle'
        ];
        if (recentBundles.isEmpty()) return;

        Set<Id> quoteIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem b : recentBundles) {
            quoteIds.add(b.QuoteId);
            productIds.add(b.Product2Id);
        }

        Map<String, List<QuoteLineItem>> bundlesByKey = new Map<String, List<QuoteLineItem>>();
        for (QuoteLineItem b : [
            SELECT Id, QuoteId, Product2Id, CreatedDate
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds AND Product2Id IN :productIds AND Product2.Type = 'Bundle'
            ORDER BY CreatedDate ASC
        ]) {
            String key = b.QuoteId + '|' + b.Product2Id;
            if (!bundlesByKey.containsKey(key)) bundlesByKey.put(key, new List<QuoteLineItem>());
            bundlesByKey.get(key).add(b);
        }

        List<QuoteLineItem> toDelete = new List<QuoteLineItem>();
        for (List<QuoteLineItem> bundles : bundlesByKey.values()) {
            if (bundles.size() < 2) continue;
            for (Integer i = 1; i < bundles.size(); i++) toDelete.add(bundles[i]);
        }
        if (!toDelete.isEmpty()) {
            // Children of deleted bundles are independent QLIs (not platform-linked, since
            // ParentQuoteLineItemId is null on Apex-inserted children) — they stay on the quote.
            // The duplicate-bundle problem is purely the parent line; children are fine where they are.
            delete toDelete;
        }
    }


    /**
     * Apply attribute-based price adjustments to Bundle QLIs in beforeUpdate by mutating
     * Trigger.new in-place (no DML).
     *
     * Data source: Techno_Attribute_Price_Rule__mdt custom metadata records. Each record is a
     * (ProductId, AttributeDefinitionId, AttributeValue) → AdjustmentValue mapping. We sum
     * adjustments for each attribute the user selected on the bundle and rebase UnitPrice from
     * PricebookEntry.UnitPrice + total. Idempotent — repeat fires produce the same result.
     *
     * Why custom metadata instead of native AttributeBasedAdjustment / AttributeAdjustmentCondition:
     *   The native Salesforce Pricing objects can only be written through the Pricing Procedure
     *   Builder UI's internal endpoint. Direct Apex/REST DML is blocked by a platform validation
     *   ("FIELD_INTEGRITY_EXCEPTION: Ensure that your attribute is price impacting") that no
     *   combination of IsPriceImpacting flags or sync actions can satisfy outside the Builder UI.
     *   Migrating the rule data into custom metadata sidesteps the validation entirely while
     *   preserving the same runtime behavior. If/when the Builder UI stabilizes in this org,
     *   the rule records can be re-mirrored back into the native objects (1:1 schema).
     */
    private static void applyAttributeAdjustmentsInPlace(List<QuoteLineItem> qlis) {
        if (qlis == null || qlis.isEmpty()) return;

        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : qlis) {
            if (q.Id != null) qliIds.add(q.Id);
        }
        if (qliIds.isEmpty()) return;

        // Step 1: Filter to Bundle QLIs (re-query — Trigger.new doesn't have Product2.Type)
        Map<Id, QuoteLineItem> bundleInfoById = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem qli : [
            SELECT Id, Product2Id, PricebookEntry.UnitPrice
            FROM QuoteLineItem
            WHERE Id IN :qliIds AND Product2.Type = 'Bundle'
        ]) {
            bundleInfoById.put(qli.Id, qli);
        }
        if (bundleInfoById.isEmpty()) return;

        // Step 2: Read attribute selections per QLI
        Map<Id, Map<Id, String>> qliAttrValues = new Map<Id, Map<Id, String>>();
        for (QuoteLineItemAttribute qlia : [
            SELECT QuoteLineItemId, AttributeDefinitionId, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :bundleInfoById.keySet()
        ]) {
            if (!qliAttrValues.containsKey(qlia.QuoteLineItemId)) qliAttrValues.put(qlia.QuoteLineItemId, new Map<Id, String>());
            qliAttrValues.get(qlia.QuoteLineItemId).put(qlia.AttributeDefinitionId, qlia.AttributeValue);
        }
        if (qliAttrValues.isEmpty()) return;

        // Step 3: Load active rules from custom metadata, indexed by (ProductId|AttrDefId|AttrValue)
        Map<String, Techno_Attribute_Price_Rule__mdt> rulesByKey = new Map<String, Techno_Attribute_Price_Rule__mdt>();
        for (Techno_Attribute_Price_Rule__mdt rule : [
            SELECT ProductId__c, AttributeDefinitionId__c, AttributeValue__c,
                   AdjustmentType__c, AdjustmentValue__c, IsActive__c
            FROM Techno_Attribute_Price_Rule__mdt
            WHERE IsActive__c = true
        ]) {
            String key = rule.ProductId__c + '|' + rule.AttributeDefinitionId__c + '|' + rule.AttributeValue__c;
            rulesByKey.put(key, rule);
        }
        System.debug('applyAttributeAdjustmentsInPlace: loaded ' + rulesByKey.size() + ' active pricing rules');
        if (rulesByKey.isEmpty()) return;

        // Step 4: For each bundle QLI in Trigger.new, sum adjustments and SET IN-PLACE
        for (QuoteLineItem q : qlis) {
            QuoteLineItem dbInfo = bundleInfoById.get(q.Id);
            if (dbInfo == null) continue;
            Map<Id, String> selectedAttrs = qliAttrValues.get(q.Id);
            if (selectedAttrs == null || selectedAttrs.isEmpty()) continue;
            if (dbInfo.PricebookEntry == null || dbInfo.PricebookEntry.UnitPrice == null) continue;

            Decimal totalAdjustment = 0;
            for (Id attrDefId : selectedAttrs.keySet()) {
                String selectedValue = selectedAttrs.get(attrDefId);
                if (String.isBlank(selectedValue)) continue;
                String key = dbInfo.Product2Id + '|' + attrDefId + '|' + selectedValue;
                Techno_Attribute_Price_Rule__mdt rule = rulesByKey.get(key);
                if (rule == null) continue;

                if (rule.AdjustmentType__c == 'Amount') {
                    totalAdjustment += rule.AdjustmentValue__c;
                } else if (rule.AdjustmentType__c == 'Percent') {
                    totalAdjustment += (dbInfo.PricebookEntry.UnitPrice * rule.AdjustmentValue__c / 100);
                }
            }

            // Idempotent — always rebase from PricebookEntry.UnitPrice, not from q.UnitPrice
            Decimal newUnitPrice = (dbInfo.PricebookEntry.UnitPrice + totalAdjustment).setScale(2);
            System.debug('applyAttributeAdjustmentsInPlace: QLI ' + q.Id + ' base=' + dbInfo.PricebookEntry.UnitPrice + ' adj=' + totalAdjustment + ' new=' + newUnitPrice);
            q.UnitPrice = newUnitPrice;
        }
    }

    /**
     * Enforce industry-based POS Solutions eligibility at QuoteLineItem save time.
     *
     * The native Browse Catalog runtime engine does NOT enforce ProductDisqualification.Industry__c
     * blocks in this org configuration — products show in the catalog regardless of Account industry.
     * This trigger is the safety net: it blocks DML (insert / update) when a POS Solutions product
     * is being added to a Quote whose Account is not in the Retail industry.
     *
     * POS product codes hard-coded for transparency. Add new POS codes here when introducing them.
     * Returns custom errors via addError() so the user sees a clear, demo-friendly message instead
     * of a low-level platform exception (PlaceSalesTransactionPersistException) from the
     * Industries CPQ cart persistence layer.
     */
    private static final Set<String> POS_PRODUCT_CODES = new Set<String>{'POS01', 'ENPOS101', 'REG01', 'SCN01'};

    private static void enforcePOSIndustryEligibility(List<QuoteLineItem> qlis) {
        if (qlis == null || qlis.isEmpty()) return;

        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem q : qlis) {
            if (q.Product2Id != null) productIds.add(q.Product2Id);
        }
        if (productIds.isEmpty()) return;

        Map<Id, Product2> productMap = new Map<Id, Product2>([
            SELECT Id, ProductCode FROM Product2 WHERE Id IN :productIds AND ProductCode IN :POS_PRODUCT_CODES
        ]);
        if (productMap.isEmpty()) return;

        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem q : qlis) {
            if (productMap.containsKey(q.Product2Id) && q.QuoteId != null) quoteIds.add(q.QuoteId);
        }
        if (quoteIds.isEmpty()) return;

        Map<Id, String> industryByQuote = new Map<Id, String>();
        for (Quote q : [SELECT Id, AccountId, Account.Industry FROM Quote WHERE Id IN :quoteIds]) {
            industryByQuote.put(q.Id, q.Account != null ? q.Account.Industry : null);
        }

        for (QuoteLineItem qli : qlis) {
            if (!productMap.containsKey(qli.Product2Id)) continue;
            String industry = industryByQuote.get(qli.QuoteId);
            if (industry != 'Retail') {
                qli.Product2Id.addError('POS Solutions are reserved for Retail-industry customers. This account is in ' + (industry == null ? 'a non-Retail industry' : industry) + ', so this product cannot be added to the quote.');
            }
        }
    }

    private static void recalculateQuoteTax(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) return;

        Map<Id, Decimal> taxByQuote = new Map<Id, Decimal>();
        for (Id qid : quoteIds) taxByQuote.put(qid, 0);

        for (AggregateResult ar : [
            SELECT QuoteId qid, SUM(TotalPrice) totalPriceSum
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
            GROUP BY QuoteId
        ]) {
            Id qid = (Id) ar.get('qid');
            Decimal totalPrice = (Decimal) ar.get('totalPriceSum');
            if (totalPrice == null) totalPrice = 0;
            taxByQuote.put(qid, (totalPrice * VAT_RATE).setScale(2));
        }

        List<Quote> toUpdate = new List<Quote>();
        for (Id qid : taxByQuote.keySet()) {
            toUpdate.add(new Quote(Id = qid, Tax = taxByQuote.get(qid)));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
