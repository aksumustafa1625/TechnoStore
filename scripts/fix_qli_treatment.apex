// Re-bind all QuoteLineItems on the 4 demo quotes to TechStore VAT 19 Treatment
// Then deactivate the orphan US treatment so it stops being auto-picked on new lines

Id vatTreatmentId = '1ttaj000000BaxpAAC';
Id usTreatmentId = '1ttaj0000009UWjAAM';

Set<Id> demoQuoteIds = new Set<Id>{
    '0Q0aj000002IHajCAG', '0Q0aj000002IHakCAG',
    '0Q0aj000002IHalCAG', '0Q0aj000002IHamCAG'
};

List<QuoteLineItem> qlis = [
    SELECT Id, Quote.Name, Product2.Name, TaxTreatmentId
    FROM QuoteLineItem
    WHERE QuoteId IN :demoQuoteIds
];

System.debug('QLIs found: ' + qlis.size());
for (QuoteLineItem qli : qlis) qli.TaxTreatmentId = vatTreatmentId;
update qlis;
System.debug('Updated all QLIs to VAT treatment');

// Skip US treatment deactivation — it's set as org-wide default (UI only)
System.debug('Skipping US treatment deactivation (org-wide default lock)');

// Verify
List<QuoteLineItem> verifyQlis = [SELECT Id, Quote.Name, Product2.Name, TaxTreatmentId FROM QuoteLineItem WHERE QuoteId IN :demoQuoteIds];
for (QuoteLineItem q : verifyQlis) System.debug(q.Quote.Name + ' / ' + q.Product2.Name + ' -> ' + q.TaxTreatmentId);
