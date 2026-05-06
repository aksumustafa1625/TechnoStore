/**
 * Trigger handler for QuoteLineItem.
 *
 * Responsibilities:
 *   1. Auto-populate Description from Product2.Name (for CLM contract conversion).
 *   2. Recalculate Quote.Tax = SUM(line VAT 19%) on every QLI insert/update/delete/undelete,
 *      so that Quote Summary panel + Grand Total reflect estimated VAT without needing
 *      the (Invoice-only) Tax Engine adapter to fire.
 *   3. On Bundle QLI insert, create Quote_Bundle_Component__c display records (NOT child QLIs)
 *      so the bundleIncludedComponents LWC can render the included items on the Quote page.
 *      We do not insert child QuoteLineItems because the platform-managed
 *      ParentQuoteLineItemId field is non-writeable from Apex, which would leave the children
 *      as orphans and trigger Configure UI's "Required fields missing: [Price Book Entry]" toast.
 *   4. Apply attribute-based price adjustments on Bundle QLIs in beforeUpdate by mutating
 *      Trigger.new in-place (no DML), based on the AttributeBasedAdjustment data layer.
 *
 * Extends Kevin O'Hara TriggerHandler framework.
 */
public with sharing class QuoteLineItemTriggerHandler extends TriggerHandler {

    private static final Decimal VAT_RATE = 0.19;

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
        createBundleComponentDisplays(records);
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
     * Create Quote_Bundle_Component__c display records for each newly-inserted Bundle QLI.
     * These are NOT child QuoteLineItems — they exist purely so the bundleIncludedComponents LWC
     * can render the bundle's included items on the Quote page. We do not insert child
     * QuoteLineItems because the platform-managed ParentQuoteLineItemId field is non-writeable
     * from Apex, which leaves the children as orphans and causes Configure UI's Save & Exit
     * validation to throw a misleading "Required fields missing: [Price Book Entry]" toast.
     * The component records are scoped to the parent QLI; they cascade-delete when the parent
     * QLI or Quote is deleted (via Cascade lookup constraint).
     */
    private static void createBundleComponentDisplays(List<QuoteLineItem> newQlis) {
        if (newQlis == null || newQlis.isEmpty()) return;

        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem q : newQlis) {
            if (q.Id != null) qliIds.add(q.Id);
        }
        if (qliIds.isEmpty()) return;

        // Filter to bundle QLIs only (re-query for Product2.Type)
        Map<Id, QuoteLineItem> bundleParentQlis = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : [
            SELECT Id, QuoteId, Product2Id
            FROM QuoteLineItem
            WHERE Id IN :qliIds AND Product2.Type = 'Bundle'
        ]) {
            bundleParentQlis.put(q.Id, q);
        }
        if (bundleParentQlis.isEmpty()) return;

        // Skip QLIs that already have component display records (Configure UI re-insert guard)
        Set<Id> qlisWithDisplays = new Set<Id>();
        for (Quote_Bundle_Component__c existing : [
            SELECT Parent_Quote_Line_Item__c
            FROM Quote_Bundle_Component__c
            WHERE Parent_Quote_Line_Item__c IN :bundleParentQlis.keySet()
        ]) {
            qlisWithDisplays.add(existing.Parent_Quote_Line_Item__c);
        }
        for (Id qid : qlisWithDisplays) bundleParentQlis.remove(qid);
        if (bundleParentQlis.isEmpty()) return;

        // Collect parent product IDs to look up their default components
        Set<Id> parentProductIds = new Set<Id>();
        for (QuoteLineItem q : bundleParentQlis.values()) parentProductIds.add(q.Product2Id);

        // Load default components with child product names (ChildProduct.Name needed for display)
        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ChildProduct.Name, ChildProduct.BasedOnId,
                   Quantity, IsDefaultComponent
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :parentProductIds AND IsDefaultComponent = true
        ];
        if (components.isEmpty()) return;

        // Look up parent bundle BasedOn classifications so we can skip components whose
        // classification matches the bundle's own (those represent attributes set via Configure UI,
        // not separate displayable items).
        Map<Id, Id> bundleClassificationByProduct = new Map<Id, Id>();
        for (Product2 p : [
            SELECT Id, BasedOnId FROM Product2 WHERE Id IN :parentProductIds AND BasedOnId != null
        ]) {
            bundleClassificationByProduct.put(p.Id, p.BasedOnId);
        }

        Map<Id, List<ProductRelatedComponent>> componentsByParent = new Map<Id, List<ProductRelatedComponent>>();
        for (ProductRelatedComponent c : components) {
            Id parentClassif = bundleClassificationByProduct.get(c.ParentProductId);
            Id childClassif = c.ChildProduct != null ? c.ChildProduct.BasedOnId : null;
            if (parentClassif != null && childClassif == parentClassif) continue;
            if (!componentsByParent.containsKey(c.ParentProductId)) componentsByParent.put(c.ParentProductId, new List<ProductRelatedComponent>());
            componentsByParent.get(c.ParentProductId).add(c);
        }

        List<Quote_Bundle_Component__c> displays = new List<Quote_Bundle_Component__c>();
        for (QuoteLineItem parent : bundleParentQlis.values()) {
            List<ProductRelatedComponent> kids = componentsByParent.get(parent.Product2Id);
            if (kids == null) continue;
            for (ProductRelatedComponent c : kids) {
                Quote_Bundle_Component__c display = new Quote_Bundle_Component__c();
                display.Quote__c = parent.QuoteId;
                display.Parent_Quote_Line_Item__c = parent.Id;
                display.Bundle_Product__c = parent.Product2Id;
                display.Component_Product__c = c.ChildProductId;
                display.Component_Name__c = (c.ChildProduct != null) ? c.ChildProduct.Name : null;
                display.Quantity__c = (c.Quantity != null) ? c.Quantity : 1;
                display.Included_In_Bundle__c = true;
                display.Display_Price__c = 0;
                display.Is_Default_Component__c = true;
                displays.add(display);
            }
        }

        if (!displays.isEmpty()) insert displays;
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
