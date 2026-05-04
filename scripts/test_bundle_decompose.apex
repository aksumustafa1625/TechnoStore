// Test: programmatically add Home Office Bundle to Köln quote → trigger should decompose
Id kolnQuoteId = '0Q0aj000002IHalCAG';
Id homeOfficeBundleProdId = '01taj00000Qp7IFAAZ';

// Find PricebookEntry for the bundle in Standard Price Book
Quote q = [SELECT Pricebook2Id FROM Quote WHERE Id=:kolnQuoteId];
System.debug('Quote pricebook: ' + q.Pricebook2Id);

PricebookEntry pbe = [
    SELECT Id, UnitPrice
    FROM PricebookEntry
    WHERE Product2Id=:homeOfficeBundleProdId AND Pricebook2Id=:q.Pricebook2Id AND IsActive=true
    LIMIT 1
];
System.debug('Bundle PBE: ' + pbe.Id + ' Price=' + pbe.UnitPrice);

// Insert parent bundle QLI — trigger should auto-add 5 children
QuoteLineItem parentQli = new QuoteLineItem();
parentQli.QuoteId = kolnQuoteId;
parentQli.Product2Id = homeOfficeBundleProdId;
parentQli.PricebookEntryId = pbe.Id;
parentQli.Quantity = 1;
parentQli.UnitPrice = pbe.UnitPrice;
insert parentQli;
System.debug('Inserted parent: ' + parentQli.Id);

// Verify all QLIs on quote
List<QuoteLineItem> all = [
    SELECT Id, Product2.Name, Product2.Type, UnitPrice, Quantity, TotalPrice
    FROM QuoteLineItem WHERE QuoteId=:kolnQuoteId ORDER BY CreatedDate
];
System.debug('--- Total QLIs after insert: ' + all.size() + ' ---');
for (QuoteLineItem qli : all) {
    System.debug(qli.Product2.Name + ' (' + qli.Product2.Type + ') Qty=' + qli.Quantity + ' UnitPrice=' + qli.UnitPrice + ' Total=' + qli.TotalPrice);
}
