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
 *   4. Apply attribute-based price adjustments on Bundle QLIs in beforeUpdate by mutating
 *      Trigger.new in-place (no DML), based on the AttributeBasedAdjustment data layer.
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
    }

    protected override void beforeUpdate() {
        autoPopulateDescription();
        applyAttributeAdjustmentsInPlace(records);
    }

    protected override void afterInsert() {
        autoDecomposeBundles(records);
        recalculateQuoteTax(quoteIdsFromRecords(records));
    }

    protected override void afterUpdate() {
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
     * Auto-decompose Bundle parent QLIs into child QLIs on after-insert.
     * For each bundle QLI, find its ProductRelatedComponent records (IsDefaultComponent=true)
     * and create matching child QLIs on the same Quote at $0 (bundle parent covers the price).
     *
     * Known limitation: the platform-managed QuoteLineItem.ParentQuoteLineItemId is non-writeable
     * from Apex, so children we insert remain "orphans" from the Configure UI's perspective.
     * This causes a "Required fields missing: [Price Book Entry]" red toast on Save & Exit and
     * requires the user to click "Reprice All" 1-2 times after Save & Exit for the new attribute
     * pricing to surface in the grid. Both are accepted cosmetic issues — the data layer is
     * correct (UnitPrice persists at the adjusted value, Quote.Tax is recalculated).
     *
     * Dedupe guards below prevent the toast from cascading worse: Configure UI internally
     * inserts transient draft bundles during Save & Exit, and without these guards each draft
     * would get its own 3 phantom children, ballooning the quote to 12+ QLIs.
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

        // Skip decomposition if a bundle of the same Product2 already exists on the same Quote —
        // that earlier bundle is the user's intentional add. The new insert is virtually always a
        // Configure UI Save & Exit transient draft.
        Set<Id> quoteIdsForCheck = new Set<Id>();
        Set<Id> productIdsForCheck = new Set<Id>();
        Set<Id> currentQliIds = bundleParentQlis.keySet();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            quoteIdsForCheck.add(q.QuoteId);
            productIdsForCheck.add(q.Product2Id);
        }
        Set<String> existingBundleKeys = new Set<String>();
        for (QuoteLineItem existing : [
            SELECT QuoteId, Product2Id
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIdsForCheck
              AND Product2Id IN :productIdsForCheck
              AND Id NOT IN :currentQliIds
        ]) {
            existingBundleKeys.add(existing.QuoteId + '|' + existing.Product2Id);
        }
        Map<Id, QuoteLineItem> filteredBundleParents = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : bundleParentQlis.values()) {
            String key = q.QuoteId + '|' + q.Product2Id;
            if (existingBundleKeys.contains(key)) continue;
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
            SELECT Id, ParentProductId, ChildProductId, ChildProduct.BasedOnId,
                   Quantity, IsDefaultComponent
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

        // Per-(Quote,ChildProduct) dedupe guard: prevents Configure UI re-insert from duplicating children.
        Set<Id> quoteIdsInScope = new Set<Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) quoteIdsInScope.add(q.QuoteId);
        Set<String> existingChildKeys = new Set<String>();
        for (QuoteLineItem existing : [
            SELECT QuoteId, Product2Id
            FROM QuoteLineItem
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
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice,
                   ProductSellingModelId, ProductSellingModel.SellingModelType
            FROM PricebookEntry
            WHERE Product2Id IN :childProductIds AND Pricebook2Id IN :pricebookIds AND IsActive = true
        ]) {
            pbeKeyToEntry.put(pbe.Pricebook2Id + '|' + pbe.Product2Id, pbe);
        }

        List<QuoteLineItem> childQlis = new List<QuoteLineItem>();
        for (QuoteLineItem parent : bundleParentQlis.values()) {
            List<ProductRelatedComponent> kids = childrenByParent.get(parent.Product2Id);
            if (kids == null) continue;
            Id parentPricebookId = (parent.PricebookEntry != null) ? parent.PricebookEntry.Pricebook2Id : null;
            for (ProductRelatedComponent c : kids) {
                if (existingChildKeys.contains(parent.QuoteId + '|' + c.ChildProductId)) continue;
                String key = parentPricebookId + '|' + c.ChildProductId;
                PricebookEntry pbe = pbeKeyToEntry.get(key);
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
     * Apply attribute-based price adjustments to Bundle QLIs based on QuoteLineItemAttribute
     * selections. Runs synchronously in beforeUpdate() and mutates Trigger.new in-place — no DML.
     *
     * Production-equivalent to the native Pricing Procedure with Attribute-Based Price element —
     * consumes the SAME AttributeBasedAdjustment + AttributeAdjustmentCondition records the
     * native engine would consume.
     *
     * Why beforeUpdate (not @future):
     *   The previous @future approach avoided a "Required fields missing: [Price Book Entry]"
     *   toast caused by sync DML conflicting with Save & Exit's internal repricing. Setting
     *   UnitPrice directly on Trigger.new sidesteps DML entirely, so the conflict can't occur.
     *
     * Why beforeUpdate (not beforeInsert):
     *   QuoteLineItemAttribute records are populated by Configure UI AFTER the parent QLI is
     *   inserted. They first become queryable when Save & Exit causes the parent QLI update.
     */
    private static void applyAttributeAdjustmentsInPlace(List<QuoteLineItem> qlis) {
        if (qlis == null || qlis.isEmpty()) return;

        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : qlis) {
            if (q.Id != null) qliIds.add(q.Id);
        }
        if (qliIds.isEmpty()) return;

        // Step 1: Filter to Bundle QLIs (re-query because Trigger.new doesn't have Product2.Type)
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
        System.debug('applyAttributeAdjustmentsInPlace: found QLIA for ' + qliAttrValues.size() + ' bundle QLIs out of ' + bundleInfoById.size());
        if (qliAttrValues.isEmpty()) return;

        // Step 3: Load active adjustments for all bundle products in scope
        Set<Id> bundleProductIds = new Set<Id>();
        for (QuoteLineItem qli : bundleInfoById.values()) bundleProductIds.add(qli.Product2Id);

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

        // Step 5: For each bundle QLI in Trigger.new, compute newUnitPrice and SET IN-PLACE
        for (QuoteLineItem q : qlis) {
            QuoteLineItem dbInfo = bundleInfoById.get(q.Id);
            if (dbInfo == null) continue;
            Map<Id, String> selectedAttrs = qliAttrValues.get(q.Id);
            if (selectedAttrs == null || selectedAttrs.isEmpty()) continue;

            List<AttributeBasedAdjustment> productAdjustments = adjustmentsByProduct.get(dbInfo.Product2Id);
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
                    else if (adj.AdjustmentType == 'Percent' && dbInfo.PricebookEntry != null && dbInfo.PricebookEntry.UnitPrice != null) {
                        totalAdjustment += (dbInfo.PricebookEntry.UnitPrice * adj.AdjustmentValue / 100);
                    }
                }
            }

            // Always rebase from PricebookEntry.UnitPrice (the immutable list price), not from
            // q.UnitPrice — that way repeat fires of beforeUpdate produce idempotent results.
            if (dbInfo.PricebookEntry == null || dbInfo.PricebookEntry.UnitPrice == null) continue;
            Decimal newUnitPrice = (dbInfo.PricebookEntry.UnitPrice + totalAdjustment).setScale(2);
            System.debug('applyAttributeAdjustmentsInPlace: QLI ' + q.Id + ' base=' + dbInfo.PricebookEntry.UnitPrice + ' adj=' + totalAdjustment + ' new=' + newUnitPrice);
            q.UnitPrice = newUnitPrice;
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
