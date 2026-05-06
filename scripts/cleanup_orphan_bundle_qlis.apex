// Cleanup: delete all orphan bundle child QLIs from Köln test quote
// Run after switching to the LWC-based component display approach.

Id quoteId = '0Q0aj000002IHalCAG';

// Find Bundle QLIs and the children we previously inserted (UnitPrice=0 + 3 specific products)
Set<Id> targetChildProducts = new Set<Id>{
    '01taj00000QnnmWAAR', // Wireless Combo Set
    '01taj00000QnnmXAAR', // ErgoMouse Vertical
    '01taj00000Qnnm1AAB'  // WebCam Pro 4K Studio
};

List<QuoteLineItem> toDelete = [
    SELECT Id, Product2.Name, UnitPrice, Product2.Type
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId
      AND (Product2Id IN :targetChildProducts OR Product2.Type = 'Bundle')
    ORDER BY Product2.Type DESC NULLS LAST, LineNumber
];

System.debug('Found ' + toDelete.size() + ' QLIs to delete:');
for (QuoteLineItem q : toDelete) {
    System.debug('  - ' + q.Product2.Name + ' (UnitPrice=' + q.UnitPrice + ', Type=' + q.Product2.Type + ')');
}

delete toDelete;
System.debug('Deleted ' + toDelete.size() + ' orphan QLIs from quote');
