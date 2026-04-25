List<QuoteLineItem> qlis = [SELECT Id, TaxTreatmentId, TotalTaxAmount FROM QuoteLineItem WHERE Quote.QuoteNumber = '00000075'];
for (QuoteLineItem q : qlis) { q.TaxTreatmentId = null; }
update qlis;
System.debug('Cleared TaxTreatmentId on ' + qlis.size() + ' line items. Click Reprice All.');
