/**
 * Invocable action to decompose Bundle QLIs into child QLIs on a Quote.
 *
 * Why this exists as an invocable instead of an after-insert trigger:
 *   When children are inserted DURING Configure UI's Save & Exit transaction, the managed LWC
 *   sees the new child QLIs but cannot map them in its in-memory session (children have
 *   ParentQuoteLineItemId=null, which is platform-set and non-writeable from Apex). The LWC then
 *   throws a misleading "Required fields missing: [Price Book Entry]" toast and the user has to
 *   click Reprice All 1-2 times to converge.
 *
 *   By moving decomposition out of the trigger and into an explicit user-invoked action that
 *   runs AFTER Save & Exit completes, the Configure UI's session has already closed and its
 *   commit-time validation has already passed. The orphan children are now harmless — they
 *   simply render in the grid as $0 child line items.
 *
 * Wired up via:
 *   - Decompose_Bundles_Flow (auto-launched flow that calls this invocable)
 *   - "Decompose Bundles" Quote quick action that triggers the flow
 */
public with sharing class BundleDecompositionAction {

    public class Request {
        @InvocableVariable(required=true label='Quote Id')
        public Id quoteId;
    }

    public class Result {
        @InvocableVariable(label='Number of child QLIs created')
        public Integer childrenCreated;
        @InvocableVariable(label='Status message')
        public String statusMessage;
    }

    @InvocableMethod(label='Decompose Bundle Quote Line Items' description='For each Bundle QLI on the given Quote, inserts default child QLIs based on ProductRelatedComponent (IsDefaultComponent=true). Included components are $0; add-on components use their Price Book price.')
    public static List<Result> decompose(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> quoteIds = new Set<Id>();
        for (Request r : requests) if (r.quoteId != null) quoteIds.add(r.quoteId);
        if (quoteIds.isEmpty()) {
            for (Request r : requests) {
                Result res = new Result();
                res.childrenCreated = 0;
                res.statusMessage = 'No Quote Id provided.';
                results.add(res);
            }
            return results;
        }

        Map<Id, QuoteLineItem> bundleParentQlis = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem q : [
            SELECT Id, QuoteId, Product2Id, Product2.Type, Product2.BasedOnId,
                   Quantity, PricebookEntryId, PricebookEntry.Pricebook2Id
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds AND Product2.Type = 'Bundle'
        ]) {
            bundleParentQlis.put(q.Id, q);
        }
        if (bundleParentQlis.isEmpty()) {
            for (Request r : requests) {
                Result res = new Result();
                res.childrenCreated = 0;
                res.statusMessage = 'No Bundle line items found on this quote.';
                results.add(res);
            }
            return results;
        }

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

        Map<Id, List<ProductRelatedComponent>> childrenByParent = new Map<Id, List<ProductRelatedComponent>>();
        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent c : components) {
            if (!childrenByParent.containsKey(c.ParentProductId)) childrenByParent.put(c.ParentProductId, new List<ProductRelatedComponent>());
            childrenByParent.get(c.ParentProductId).add(c);
            childProductIds.add(c.ChildProductId);
        }

        // Skip child products already on the quote — caller may invoke this action multiple times
        // and we want the operation to be idempotent.
        Set<String> existingChildKeys = new Set<String>(); // QuoteId|Product2Id
        for (QuoteLineItem existing : [
            SELECT QuoteId, Product2Id
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds AND Product2Id IN :childProductIds
        ]) {
            existingChildKeys.add(existing.QuoteId + '|' + existing.Product2Id);
        }

        // Look up PricebookEntries for child products in each pricebook in scope
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

        // Track keys already queued for insert in THIS run, so duplicate Bundle QLIs of the same
        // Product2 (e.g., a Configure UI transient that got committed alongside the user's
        // intentional bundle) don't each get their own copy of the children.
        Set<String> alreadyQueued = new Set<String>();
        List<QuoteLineItem> childQlis = new List<QuoteLineItem>();
        for (QuoteLineItem parent : bundleParentQlis.values()) {
            List<ProductRelatedComponent> kids = childrenByParent.get(parent.Product2Id);
            if (kids == null) continue;
            Id parentPricebookId = (parent.PricebookEntry != null) ? parent.PricebookEntry.Pricebook2Id : null;
            for (ProductRelatedComponent c : kids) {
                String childKey = parent.QuoteId + '|' + c.ChildProductId;
                if (existingChildKeys.contains(childKey)) continue;
                if (alreadyQueued.contains(childKey)) continue;
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
                alreadyQueued.add(childKey);
            }
        }

        if (!childQlis.isEmpty()) insert childQlis;

        for (Request r : requests) {
            Result res = new Result();
            res.childrenCreated = childQlis.size();
            res.statusMessage = (childQlis.isEmpty())
                ? 'All bundle components already on the quote — nothing to add.'
                : childQlis.size() + ' bundle component(s) added to the quote.';
            results.add(res);
        }
        return results;
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
}
