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

    @InvocableMethod(label='Decompose Bundle Quote Line Items' description='For each Bundle QLI on the given Quote, inserts default child QLIs at $0 based on ProductRelatedComponent (IsDefaultComponent=true). Skips Bundles that already have decomposed children.')
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
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModel.SellingModelType
            FROM PricebookEntry
            WHERE Product2Id IN :childProductIds AND Pricebook2Id IN :pricebookIds AND IsActive = true
        ]) {
            pbeKeyToEntry.put(pbe.Pricebook2Id + '|' + pbe.Product2Id, pbe);
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
                child.UnitPrice = 0;
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
}
