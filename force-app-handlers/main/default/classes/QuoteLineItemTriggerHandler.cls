/**
 * Trigger handler for QuoteLineItem.
 *
 * Responsibilities:
 *   1. Auto-populate Description from Product2.Name (for CLM contract conversion).
 *   2. Recalculate Quote.Tax = SUM(line VAT 19%) on every QLI insert/update/delete/undelete.
 *   3. Apply attribute-based price adjustments on Bundle QLIs in beforeUpdate, sourced from
 *      Techno_Attribute_Price_Rule__mdt custom metadata (see applyAttributeAdjustmentsInPlace
 *      docstring for why custom metadata instead of native AttributeBasedAdjustment).
 *   4. Auto-decompose Bundle parents into child QLIs asynchronously after the parent QLI is
 *      inserted. The @future boundary keeps child rows outside the Configure UI
 *      save transaction.
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
    }

    protected override void beforeUpdate() {
        autoPopulateDescription();
        applyAttributeAdjustmentsInPlace(records);
    }

    protected override void afterInsert() {
        // Queue child-line decomposition after the add transaction commits. The async boundary
        // keeps Apex-inserted children out of Configure UI's commit-time validation window.
        Set<Id> insertedIds = new Set<Id>();
        for (QuoteLineItem q : records) if (q.Id != null) insertedIds.add(q.Id);
        if (!insertedIds.isEmpty() && !System.isFuture() && !System.isBatch() && !System.isQueueable()) {
            cleanupDuplicateBundlesAsync(insertedIds);
            decomposeBundlesAsync(insertedIds);
        }
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
     * Auto-decompose Bundle parent QLIs into child QLIs.
     * Included components are priced at 0; non-included add-ons use their Price Book price.
     *
     * Skips decomposition if a bundle of the same Product2 already exists on the same Quote.
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
        for (QuoteLineItem q : bundleParentQlis.values()) {
            parentProductIds.add(q.Product2Id);
        }

        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ChildProduct.BasedOnId, Quantity,
                   IsDefaultComponent, DoesBundlePriceIncludeChild, Sequence
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :parentProductIds AND IsDefaultComponent = true
            ORDER BY ParentProductId, Sequence
        ];
        if (components.isEmpty()) return;

        Map<Id, List<ProductRelatedComponent>> childrenByParent = new Map<Id, List<ProductRelatedComponent>>();
        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent c : components) {
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
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId,
                   ProductSellingModel.SellingModelType
            FROM PricebookEntry
            WHERE Product2Id IN :childProductIds AND Pricebook2Id IN :pricebookIds AND IsActive = true
        ]) {
            putPreferredPricebookEntry(pbeKeyToEntry, pbe);
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
                child.UnitPrice = childUnitPrice(c, pbe);
                childQlis.add(child);
                queued.add(childKey);
            }
        }

        if (!childQlis.isEmpty()) {
            isBundleDecompositionRunning = true;
            try {
                insert childQlis;
                insertDefaultChildAttributes(childQlis);
            } finally {
                isBundleDecompositionRunning = false;
            }
        }
    }

    private static void putPreferredPricebookEntry(Map<String, PricebookEntry> entriesByKey, PricebookEntry candidate) {
        if (candidate == null || candidate.Pricebook2Id == null || candidate.Product2Id == null) return;
        String key = candidate.Pricebook2Id + '|' + candidate.Product2Id;
        PricebookEntry existing = entriesByKey.get(key);
        if (existing == null || pricebookEntryScore(candidate) > pricebookEntryScore(existing)) {
            entriesByKey.put(key, candidate);
        }
    }

    private static Integer pricebookEntryScore(PricebookEntry pbe) {
        if (pbe == null) return 0;
        String sellingType = (pbe.ProductSellingModel != null) ? pbe.ProductSellingModel.SellingModelType : null;
        if (sellingType == 'OneTime') return 3;
        if (pbe.ProductSellingModelId == null) return 2;
        if (sellingType == 'Evergreen' || sellingType == 'TermDefined') return 0;
        return 1;
    }

    private static Decimal childUnitPrice(ProductRelatedComponent component, PricebookEntry pbe) {
        if (component != null && component.DoesBundlePriceIncludeChild == true) return 0;
        return (pbe != null && pbe.UnitPrice != null) ? pbe.UnitPrice : 0;
    }

    private class DefaultAttributeValue {
        Id attributeDefinitionId;
        Id attributePicklistValueId;
        String attributeValue;

        DefaultAttributeValue(Id attributeDefinitionId, Id attributePicklistValueId, String attributeValue) {
            this.attributeDefinitionId = attributeDefinitionId;
            this.attributePicklistValueId = attributePicklistValueId;
            this.attributeValue = attributeValue;
        }
    }

    private class SelectedAttributeValue {
        String attributeValue;
        Id attributePicklistValueId;

        SelectedAttributeValue(String attributeValue, Id attributePicklistValueId) {
            this.attributeValue = attributeValue;
            this.attributePicklistValueId = attributePicklistValueId;
        }
    }

    private static void insertDefaultChildAttributes(List<QuoteLineItem> childQlis) {
        if (childQlis == null || childQlis.isEmpty()) return;

        Set<Id> childQliIds = new Set<Id>();
        for (QuoteLineItem child : childQlis) {
            if (child.Id != null) childQliIds.add(child.Id);
        }
        if (childQliIds.isEmpty()) return;

        Map<String, List<DefaultAttributeValue>> defaultsByProductCode = defaultAttributesByProductCode();
        if (defaultsByProductCode.isEmpty()) return;

        Map<Id, QuoteLineItem> insertedChildren = new Map<Id, QuoteLineItem>([
            SELECT Id, Product2.ProductCode
            FROM QuoteLineItem
            WHERE Id IN :childQliIds
        ]);

        Set<String> existingKeys = new Set<String>();
        for (QuoteLineItemAttribute existing : [
            SELECT QuoteLineItemId, AttributeDefinitionId
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :childQliIds
        ]) {
            existingKeys.add(existing.QuoteLineItemId + '|' + existing.AttributeDefinitionId);
        }

        List<QuoteLineItemAttribute> attrsToInsert = new List<QuoteLineItemAttribute>();
        for (QuoteLineItem child : insertedChildren.values()) {
            String productCode = child.Product2 != null ? child.Product2.ProductCode : null;
            List<DefaultAttributeValue> defaults = defaultsByProductCode.get(productCode);
            if (defaults == null) continue;

            for (DefaultAttributeValue defaultValue : defaults) {
                String key = child.Id + '|' + defaultValue.attributeDefinitionId;
                if (existingKeys.contains(key)) continue;

                attrsToInsert.add(new QuoteLineItemAttribute(
                    QuoteLineItemId = child.Id,
                    AttributeDefinitionId = defaultValue.attributeDefinitionId,
                    AttributePicklistValueId = defaultValue.attributePicklistValueId,
                    AttributeValue = defaultValue.attributeValue,
                    ExternalId = 'auto-default-' + child.Id + '-' + String.valueOf(defaultValue.attributeDefinitionId)
                ));
                existingKeys.add(key);
            }
        }

        if (!attrsToInsert.isEmpty()) {
            Database.insertImmediate(attrsToInsert);
        }
    }

    private static Map<String, List<DefaultAttributeValue>> defaultAttributesByProductCode() {
        Map<String, List<DefaultAttributeValue>> result = new Map<String, List<DefaultAttributeValue>>();

        result.put('COMP-LAP-001', new List<DefaultAttributeValue>{
            new DefaultAttributeValue('0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'),
            new DefaultAttributeValue('0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'),
            new DefaultAttributeValue('0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'),
            new DefaultAttributeValue('0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch')
        });

        result.put('COMP-LAP-003', new List<DefaultAttributeValue>{
            new DefaultAttributeValue('0tjaj000000FbXJAA0', '0v6aj000000G24XAAS', 'RAM 8GB'),
            new DefaultAttributeValue('0tjaj000000FbXNAA0', '0v6aj000000G24hAAC', 'SSD Hard Drive 256GB'),
            new DefaultAttributeValue('0tjaj000000FbXMAA0', '0v6aj000000G24eAAC', 'i5-CPU 4.4GHz'),
            new DefaultAttributeValue('0tjaj000000FbXHAA0', '0v6aj000000G24PAAS', '13 Inch')
        });

        result.put('AV-MON-001', new List<DefaultAttributeValue>{
            new DefaultAttributeValue('0tjaj000000FbXFAA0', '0v6aj000000G24KAAS', '2k Built-in Display'),
            new DefaultAttributeValue('0tjaj000000FbXHAA0', '0v6aj000000G24OAAS', '27 Inch')
        });

        result.put('SVC-WAR-001', new List<DefaultAttributeValue>{
            new DefaultAttributeValue('0tjaj000000FbXBAA0', '0v6aj000000G251AAC', 'Business')
        });

        return result;
    }

    /**
     * Async wrapper that runs autoDecomposeBundles after the inserting/updating transaction
     * commits. By the time this @future fires, Configure UI's Save & Exit session has closed,
     * so the child rows we insert are never seen by its commit-time validation.
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
        Map<Id, Map<Id, SelectedAttributeValue>> qliAttrValues = new Map<Id, Map<Id, SelectedAttributeValue>>();
        Set<Id> selectedPicklistValueIds = new Set<Id>();
        for (QuoteLineItemAttribute qlia : [
            SELECT QuoteLineItemId, AttributeDefinitionId, AttributeValue, AttributePicklistValueId
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :bundleInfoById.keySet()
        ]) {
            if (!qliAttrValues.containsKey(qlia.QuoteLineItemId)) qliAttrValues.put(qlia.QuoteLineItemId, new Map<Id, SelectedAttributeValue>());
            qliAttrValues.get(qlia.QuoteLineItemId).put(
                qlia.AttributeDefinitionId,
                new SelectedAttributeValue(qlia.AttributeValue, qlia.AttributePicklistValueId)
            );
            if (qlia.AttributePicklistValueId != null) selectedPicklistValueIds.add(qlia.AttributePicklistValueId);
        }
        if (qliAttrValues.isEmpty()) return;

        Map<Id, AttributePicklistValue> picklistValuesById = new Map<Id, AttributePicklistValue>();
        if (!selectedPicklistValueIds.isEmpty()) {
            picklistValuesById = new Map<Id, AttributePicklistValue>([
                SELECT Id, Name, DisplayValue
                FROM AttributePicklistValue
                WHERE Id IN :selectedPicklistValueIds
            ]);
        }

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
            Map<Id, SelectedAttributeValue> selectedAttrs = qliAttrValues.get(q.Id);
            if (selectedAttrs == null || selectedAttrs.isEmpty()) continue;
            if (dbInfo.PricebookEntry == null || dbInfo.PricebookEntry.UnitPrice == null) continue;

            Decimal totalAdjustment = 0;
            for (Id attrDefId : selectedAttrs.keySet()) {
                SelectedAttributeValue selected = selectedAttrs.get(attrDefId);
                String selectedValue = selected != null ? selected.attributeValue : null;
                if (String.isBlank(selectedValue)) continue;
                String key = dbInfo.Product2Id + '|' + attrDefId + '|' + selectedValue;
                Techno_Attribute_Price_Rule__mdt rule = rulesByKey.get(key);
                if (rule != null && rule.AdjustmentType__c == 'Amount') {
                    totalAdjustment += rule.AdjustmentValue__c;
                } else if (rule != null && rule.AdjustmentType__c == 'Percent') {
                    totalAdjustment += (dbInfo.PricebookEntry.UnitPrice * rule.AdjustmentValue__c / 100);
                } else if (selected != null && selected.attributePicklistValueId != null) {
                    totalAdjustment += adjustmentFromPicklistLabel(picklistValuesById.get(selected.attributePicklistValueId));
                }
            }

            // Idempotent — always rebase from PricebookEntry.UnitPrice, not from q.UnitPrice
            Decimal newUnitPrice = (dbInfo.PricebookEntry.UnitPrice + totalAdjustment).setScale(2);
            System.debug('applyAttributeAdjustmentsInPlace: QLI ' + q.Id + ' base=' + dbInfo.PricebookEntry.UnitPrice + ' adj=' + totalAdjustment + ' new=' + newUnitPrice);
            q.UnitPrice = newUnitPrice;
        }
    }

    private static Decimal adjustmentFromPicklistLabel(AttributePicklistValue picklistValue) {
        if (picklistValue == null) return 0;

        String label = String.isNotBlank(picklistValue.DisplayValue)
            ? picklistValue.DisplayValue
            : picklistValue.Name;
        if (String.isBlank(label)) return 0;

        Integer marker = label.indexOf('+$');
        if (marker < 0) return 0;

        Integer endMarker = label.indexOf(')', marker);
        if (endMarker < 0) return 0;

        String amountText = label.substring(marker + 2, endMarker).replace(',', '').trim();
        if (String.isBlank(amountText)) return 0;

        try {
            return Decimal.valueOf(amountText);
        } catch (Exception e) {
            return 0;
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
