/**
 * Aura-enabled controller for the bundleIncludedComponents LWC. Returns the list of bundle
 * component display records for a Quote, grouped by parent Bundle QLI.
 *
 * The LWC renders these as an "Included Components" panel on the Quote page, replacing the
 * direct child QuoteLineItem inserts that previously caused Configure UI Save & Exit to throw
 * "Required fields missing: [Price Book Entry]" toasts due to non-writeable
 * QuoteLineItem.ParentQuoteLineItemId leaving children orphaned.
 */
public with sharing class BundleIncludedComponentsController {

    public class BundleGroup {
        @AuraEnabled public String parentQliId;
        @AuraEnabled public String bundleProductName;
        @AuraEnabled public Decimal bundleUnitPrice;
        @AuraEnabled public List<Quote_Bundle_Component__c> components;

        public BundleGroup(String parentQliId, String bundleProductName, Decimal bundleUnitPrice) {
            this.parentQliId = parentQliId;
            this.bundleProductName = bundleProductName;
            this.bundleUnitPrice = bundleUnitPrice;
            this.components = new List<Quote_Bundle_Component__c>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<BundleGroup> getBundleComponents(Id quoteId) {
        if (quoteId == null) return new List<BundleGroup>();

        Map<Id, BundleGroup> groupByParentQli = new Map<Id, BundleGroup>();

        // Bundle parent QLIs on the quote (for the panel header per bundle)
        for (QuoteLineItem qli : [
            SELECT Id, Product2.Name, UnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND Product2.Type = 'Bundle'
            ORDER BY LineNumber
        ]) {
            groupByParentQli.put(qli.Id, new BundleGroup(qli.Id, qli.Product2.Name, qli.UnitPrice));
        }
        if (groupByParentQli.isEmpty()) return new List<BundleGroup>();

        // Component display records, ordered by component name for stable rendering
        for (Quote_Bundle_Component__c c : [
            SELECT Id, Component_Name__c, Component_Product__c, Quantity__c,
                   Included_In_Bundle__c, Display_Price__c, Parent_Quote_Line_Item__c
            FROM Quote_Bundle_Component__c
            WHERE Quote__c = :quoteId AND Parent_Quote_Line_Item__c IN :groupByParentQli.keySet()
            ORDER BY Component_Name__c
        ]) {
            BundleGroup g = groupByParentQli.get(c.Parent_Quote_Line_Item__c);
            if (g != null) g.components.add(c);
        }

        // Filter out bundle groups that have no components (avoids empty cards)
        List<BundleGroup> result = new List<BundleGroup>();
        for (BundleGroup g : groupByParentQli.values()) {
            if (!g.components.isEmpty()) result.add(g);
        }
        return result;
    }
}