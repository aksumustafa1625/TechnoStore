// Force tax engine to recalculate by updating each QLI
List<QuoteLineItem> qlis = [
    SELECT Id, Quantity, UnitPrice, TaxTreatmentId
    FROM QuoteLineItem
    WHERE QuoteId='0Q0aj000002IHajCAG'
];
System.debug('QLIs to touch: ' + qlis.size());
for (QuoteLineItem q : qlis) {
    System.debug('Before: Id=' + q.Id + ' Treatment=' + q.TaxTreatmentId);
}
// No-op update — just touching to fire any triggers / tax engine
update qlis;
System.debug('Update complete');

// Verify after
List<QuoteLineItem> after = [SELECT Id, Product2.Name, TotalTaxAmount FROM QuoteLineItem WHERE QuoteId='0Q0aj000002IHajCAG'];
for (QuoteLineItem q : after) {
    System.debug('After: ' + q.Product2.Name + ' Tax=' + q.TotalTaxAmount);
}
