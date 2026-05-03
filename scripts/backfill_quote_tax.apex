// Backfill Quote.Tax for the 4 demo quotes — trigger fires the recalc
Set<Id> quoteIds = new Set<Id>{
    '0Q0aj000002IHajCAG', '0Q0aj000002IHakCAG',
    '0Q0aj000002IHalCAG', '0Q0aj000002IHamCAG'
};

// Touching ANY QLI on these quotes triggers afterUpdate → recalculateQuoteTax
List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem WHERE QuoteId IN :quoteIds];
System.debug('Touching ' + qlis.size() + ' QLIs to fire trigger');
update qlis;

// Verify
for (Quote q : [SELECT Id, Name, Subtotal, Discount, TotalPrice, Tax, GrandTotal FROM Quote WHERE Id IN :quoteIds]) {
    System.debug(q.Name + ' | Subtotal=' + q.Subtotal + ' Discount=' + q.Discount + ' TotalPrice=' + q.TotalPrice + ' Tax=' + q.Tax + ' GrandTotal=' + q.GrandTotal);
}
