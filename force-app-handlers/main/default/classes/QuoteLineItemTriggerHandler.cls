/**
 * Trigger handler for QuoteLineItem.
 *
 * Responsibilities:
 *   1. Auto-populate Description from Product2.Name (for CLM contract conversion).
 *   2. Recalculate Quote.Tax = SUM(line VAT 19%) on every QLI insert/update/delete/undelete,
 *      so that Quote Summary panel + Grand Total reflect estimated VAT without needing
 *      the (Invoice-only) Tax Engine adapter to fire.
 *   3. Auto-decompose Bundle parents into child QLIs on after-insert. Workaround for the
 *      RLM platform limitation where the default Configure UI doesn't render child component
 *      cards, so children with IsDefaultComponent=true never auto-add via Save & Exit.
 *
 * Extends Kevin O'Hara TriggerHandler framework.
 */
public with sharing class QuoteLineItemTriggerHandler extends TriggerHandler {

    private static final Decimal VAT_RATE = 0.19;
    private static Boolean isBundleDecompositionRunning = false;
    private static Boolean isAttributeAdjustmentRunning = false;

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
    }

    protected override void beforeUpdate() {
        autoPopulateDescription();
    }

    protected override void afterInsert() {
        autoDecomposeBundles(records);
        recalculateQuoteTax(quoteIdsFromRecords(records));
    }

    protected override void afterUpdate() {
        // Apply attribute-based adjustments asynchronously to avoid conflicts with
        // Salesforce's in-progress Save & Exit transaction (PricebookEntry validation).
        Set<Id> bundleQliIds = new Set<Id>();
        for (QuoteLineItem q : records) bundleQliIds.add(q.Id);
        if (!bundleQliIds.isEmpty() && !isAttributeAdjustmentRunning && !System.isFuture() && !System.isBatch()) {
            applyAttributeAdjustmentsAsync(bundleQliIds);
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
     * Auto-decompose Bundle parent QLIs into child QLIs.
     * On after-insert, for any QLI whose Product2 is a Bundle, find ProductRelatedComponent
     * records (IsDefaultComponent=true) and create matching child QLIs on the same Quote.
     * Recursion guard prevents infinite loops when child QLIs trigger this same handler.
     */
    private static void autoDecomposeBundles(List<QuoteLineItem> newQlis) {
        if (isBundleDecompositionRunning) return;
        if (newQlis == null || newQlis.isEmpty()) return;

        // Collect QLI IDs to inspect
        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : newQlis) qliIds.add(q.Id);

        // Re-query the inserted QLIs with parent product type + classification info
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

        // Collect parent product IDs + their BasedOn classifications
        Set<Id> parentProductIds = new Set<Id>();
        Map<Id, Id> parentClassificationByProduct = new Map<Id, Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            parentProductIds.add(q.Product2Id);
            if (q.Product2.BasedOnId != null) parentClassificationByProduct.put(q.Product2Id, q.Product2.BasedOnId);
        }

        // Get child components — also pull child product's BasedOnId to compare
        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ChildProduct.BasedOnId,
                   Quantity, IsDefaultComponent
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :parentProductIds AND IsDefaultComponent = true
        ];
        if (components.isEmpty()) return;

        // Group children by parent product. Skip children whose BasedOnId matches the parent
        // bundle's BasedOnId — those are redundant (bundle already represents that classification
        // with attributes already set via Configure UI; adding a duplicate child just triggers
        // attribute-missing warnings).
        Map<Id, List<ProductRelatedComponent>> childrenByParent = new Map<Id, List<ProductRelatedComponent>>();
        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent c : components) {
            Id parentClassif = parentClassificationByProduct.get(c.ParentProductId);
            Id childClassif = c.ChildProduct != null ? c.ChildProduct.BasedOnId : null;
            if (parentClassif != null && childClassif == parentClassif) {
                System.debug('Skipping child with same classification as bundle parent: ' + c.ChildProductId);
                continue;
            }
            if (!childrenByParent.containsKey(c.ParentProductId)) childrenByParent.put(c.ParentProductId, new List<ProductRelatedComponent>());
            childrenByParent.get(c.ParentProductId).add(c);
            childProductIds.add(c.ChildProductId);
        }

        // Look up PricebookEntry per child product per Pricebook (with selling model info)
        Set<Id> pricebookIds = new Set<Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            if (q.PricebookEntry != null && q.PricebookEntry.Pricebook2Id != null) pricebookIds.add(q.PricebookEntry.Pricebook2Id);
        }
        Map<String, PricebookEntry> pbeKeyToEntry = new Map<String, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice,
                   ProductSellingModelId, ProductSellingModel.SellingModelType,
                   ProductSellingModel.PricingTerm, ProductSellingModel.PricingTermUnit
            FROM PricebookEntry
            WHERE Product2Id IN :childProductIds AND Pricebook2Id IN :pricebookIds AND IsActive = true
        ]) {
            pbeKeyToEntry.put(pbe.Pricebook2Id + '|' + pbe.Product2Id, pbe);
        }

        // Build child QLIs
        List<QuoteLineItem> childQlis = new List<QuoteLineItem>();
        for (QuoteLineItem parent : bundleParentQlis.values()) {
            List<ProductRelatedComponent> kids = childrenByParent.get(parent.Product2Id);
            if (kids == null) continue;
            Id parentPricebookId = (parent.PricebookEntry != null) ? parent.PricebookEntry.Pricebook2Id : null;
            for (ProductRelatedComponent c : kids) {
                String key = parentPricebookId + '|' + c.ChildProductId;
                PricebookEntry pbe = pbeKeyToEntry.get(key);
                if (pbe == null) continue;
                QuoteLineItem child = new QuoteLineItem();
                child.QuoteId = parent.QuoteId;
                child.Product2Id = c.ChildProductId;
                child.PricebookEntryId = pbe.Id;
                child.Quantity = (c.Quantity != null) ? c.Quantity : 1;
                child.UnitPrice = 0; // Bundle price covers children — children show but contribute 0 to total

                // Skip subscription / term-defined children — they need BillingTreatment which
                // can't be set via simple QLI insert. Only auto-decompose One-Time products.
                String sellingType = (pbe.ProductSellingModel != null) ? pbe.ProductSellingModel.SellingModelType : null;
                if (sellingType == 'Evergreen' || sellingType == 'TermDefined') {
                    System.debug('Skipping subscription child product: ' + c.ChildProductId + ' (' + sellingType + ')');
                    continue;
                }

                childQlis.add(child);
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
     * Async wrapper to apply adjustments AFTER Salesforce's Save & Exit transaction completes.
     * Configure UI's save flow holds locks/validations on QLI; doing the DML synchronously
     * within the trigger caused "Required fields are missing: [Price Book Entry]" errors.
     * @future runs the update in a separate transaction once Save & Exit is committed.
     */
    @future
    public static void applyAttributeAdjustmentsAsync(Set<Id> qliIds) {
        if (qliIds == null || qliIds.isEmpty()) return;
        // Build a fake List<QuoteLineItem> wrapper to reuse the sync logic
        List<QuoteLineItem> wrapper = new List<QuoteLineItem>();
        for (Id qid : qliIds) wrapper.add(new QuoteLineItem(Id = qid));
        applyAttributeAdjustmentsToBundles(wrapper);
    }

    /**
     * Apply attribute-based price adjustments to Bundle QLIs based on QuoteLineItemAttribute
     * selections. Production-equivalent to the native Pricing Procedure with Attribute-Based
     * Price element — consumes the SAME AttributeBasedAdjustment + AttributeAdjustmentCondition
     * records the native engine would consume.
     *
     * Triggered on QLI after-update because:
     *   - QuoteLineItemAttribute does not allow direct triggers
     *   - When user clicks Save & Exit in Configure UI, QLIA records are inserted AND parent
     *     QLI gets touched/updated, so this hook catches the moment selections settle.
     *
     * Recursion-guarded — when we update the QLI's UnitPrice, this same handler re-fires;
     * the static flag prevents infinite recursion.
     */
    private static void applyAttributeAdjustmentsToBundles(List<QuoteLineItem> qlis) {
        if (isAttributeAdjustmentRunning) return;
        if (qlis == null || qlis.isEmpty()) return;

        // Step 1: Filter to Bundle QLIs only
        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : qlis) qliIds.add(q.Id);

        Map<Id, QuoteLineItem> bundleQlis = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem qli : [
            SELECT Id, Product2Id, UnitPrice, PricebookEntryId,
                   PricebookEntry.UnitPrice
            FROM QuoteLineItem
            WHERE Id IN :qliIds AND Product2.Type = 'Bundle'
        ]) {
            bundleQlis.put(qli.Id, qli);
        }
        if (bundleQlis.isEmpty()) return;

        // Step 2: Read attribute selections per QLI
        Map<Id, Map<Id, String>> qliAttrValues = new Map<Id, Map<Id, String>>();
        for (QuoteLineItemAttribute qlia : [
            SELECT QuoteLineItemId, AttributeDefinitionId, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :bundleQlis.keySet()
        ]) {
            if (!qliAttrValues.containsKey(qlia.QuoteLineItemId)) qliAttrValues.put(qlia.QuoteLineItemId, new Map<Id, String>());
            qliAttrValues.get(qlia.QuoteLineItemId).put(qlia.AttributeDefinitionId, qlia.AttributeValue);
        }
        if (qliAttrValues.isEmpty()) return; // No attributes selected yet → no adjustment

        // Step 3: Load active adjustments for all bundle products in scope
        Set<Id> bundleProductIds = new Set<Id>();
        for (QuoteLineItem qli : bundleQlis.values()) bundleProductIds.add(qli.Product2Id);

        Map<Id, List<AttributeBasedAdjustment>> adjustmentsByProduct = new Map<Id, List<AttributeBasedAdjustment>>();
        Set<Id> ruleIds = new Set<Id>();
        for (AttributeBasedAdjustment a : [
            SELECT Id, ProductId, AdjustmentValue, AdjustmentType, AttributeBasedAdjRuleId
            FROM AttributeBasedAdjustment
            WHERE ProductId IN :bundleProductIds
              AND PriceAdjustmentSchedule.IsActive = true
        ]) {
            if (!adjustmentsByProduct.containsKey(a.ProductId)) adjustmentsByProduct.put(a.ProductId, new List<AttributeBasedAdjustment>());
            adjustmentsByProduct.get(a.ProductId).add(a);
            ruleIds.add(a.AttributeBasedAdjRuleId);
        }
        if (adjustmentsByProduct.isEmpty()) return;

        // Step 4: Load conditions per rule (which attribute value → which rule)
        Map<Id, List<AttributeAdjustmentCondition>> conditionsByRule = new Map<Id, List<AttributeAdjustmentCondition>>();
        for (AttributeAdjustmentCondition c : [
            SELECT Id, AttributeBasedAdjRuleId, AttributeDefinitionId, Operator, StringValue
            FROM AttributeAdjustmentCondition
            WHERE AttributeBasedAdjRuleId IN :ruleIds
        ]) {
            if (!conditionsByRule.containsKey(c.AttributeBasedAdjRuleId)) conditionsByRule.put(c.AttributeBasedAdjRuleId, new List<AttributeAdjustmentCondition>());
            conditionsByRule.get(c.AttributeBasedAdjRuleId).add(c);
        }

        // Step 5: For each bundle QLI, sum applicable adjustments + rebase UnitPrice
        List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();
        for (Id qliId : bundleQlis.keySet()) {
            QuoteLineItem qli = bundleQlis.get(qliId);
            Map<Id, String> selectedAttrs = qliAttrValues.get(qliId);
            if (selectedAttrs == null || selectedAttrs.isEmpty()) continue;

            List<AttributeBasedAdjustment> productAdjustments = adjustmentsByProduct.get(qli.Product2Id);
            if (productAdjustments == null) continue;

            Decimal totalAdjustment = 0;
            for (AttributeBasedAdjustment adj : productAdjustments) {
                List<AttributeAdjustmentCondition> conds = conditionsByRule.get(adj.AttributeBasedAdjRuleId);
                if (conds == null || conds.isEmpty()) continue;

                Boolean allMatch = true;
                for (AttributeAdjustmentCondition cond : conds) {
                    String selectedValue = selectedAttrs.get(cond.AttributeDefinitionId);
                    if (selectedValue == null) { allMatch = false; break; }
                    if (cond.Operator == 'equals' && selectedValue != cond.StringValue) { allMatch = false; break; }
                }
                if (allMatch) {
                    if (adj.AdjustmentType == 'Amount') totalAdjustment += adj.AdjustmentValue;
                    else if (adj.AdjustmentType == 'Percent' && qli.PricebookEntry != null) {
                        totalAdjustment += (qli.PricebookEntry.UnitPrice * adj.AdjustmentValue / 100);
                    }
                }
            }

            Decimal basePrice = (qli.PricebookEntry != null && qli.PricebookEntry.UnitPrice != null) ? qli.PricebookEntry.UnitPrice : qli.UnitPrice;
            Decimal newUnitPrice = (basePrice + totalAdjustment).setScale(2);

            if (qli.UnitPrice != newUnitPrice) {
                qlisToUpdate.add(new QuoteLineItem(Id = qliId, UnitPrice = newUnitPrice));
            }
        }

        if (!qlisToUpdate.isEmpty()) {
            isAttributeAdjustmentRunning = true;
            try {
                update qlisToUpdate;
            } finally {
                isAttributeAdjustmentRunning = false;
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
