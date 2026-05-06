// Delete the phantom $1,599 Home Office Bundle from Köln Quote (leftover from earlier tests).
// Keeps the configured $1,799 bundle. Also deletes its component display records.

Id quoteId = '0Q0aj000002IHalCAG';
Id bundleProductId = '01taj00000Qp7IFAAZ'; // Home Office Bundle

// Find phantom bundles (UnitPrice == 1599 — the unconfigured ones)
List<QuoteLineItem> phantomBundles = [
    SELECT Id, UnitPrice
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId AND Product2Id = :bundleProductId AND UnitPrice = 1599
];
System.debug('Found ' + phantomBundles.size() + ' phantom bundle QLI(s) to delete');

Set<Id> phantomQliIds = new Set<Id>();
for (QuoteLineItem qli : phantomBundles) phantomQliIds.add(qli.Id);

// Delete component display records linked to these phantoms
List<Quote_Bundle_Component__c> phantomDisplays = [
    SELECT Id FROM Quote_Bundle_Component__c WHERE Parent_Quote_Line_Item__c IN :phantomQliIds
];
delete phantomDisplays;
System.debug('Deleted ' + phantomDisplays.size() + ' phantom component displays');

// Delete the phantom bundles
delete phantomBundles;
System.debug('Deleted ' + phantomBundles.size() + ' phantom bundles');
