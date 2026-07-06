// Fix the current demo quotes only.
// Scope:
// - Keep Quote.LegalEntityId on TechStore Entity.
// - Bind existing QuoteLineItems to the active TechStore VAT 19 TaxTreatment.

Id techStoreEntityId = '0fwaj0000006IqHAAU';
Id vatTreatmentId = '1ttaj000000BaxpAAC';

Set<Id> demoQuoteIds = new Set<Id>{
    '0Q0aj000002hDwvCAE', // Demo Quote 1
    '0Q0aj000002hDwwCAE', // Demo Quote 2
    '0Q0aj000002hDwxCAE', // Demo Quote 3
    '0Q0aj000002hDwyCAE', // Demo Quote 4
    '0Q0aj000002hDwzCAE'  // Demo Quote 5
};

List<Quote> quotesToUpdate = new List<Quote>();
for (Quote q : [
    SELECT Id, Name, LegalEntityId
    FROM Quote
    WHERE Id IN :demoQuoteIds
]) {
    System.debug('Quote before: ' + q.Name + ' LegalEntityId=' + q.LegalEntityId);
    if (q.LegalEntityId != techStoreEntityId) {
        quotesToUpdate.add(new Quote(Id = q.Id, LegalEntityId = techStoreEntityId));
    }
}

if (!quotesToUpdate.isEmpty()) {
    update quotesToUpdate;
    System.debug('Updated Quote LegalEntityId count=' + quotesToUpdate.size());
} else {
    System.debug('No Quote LegalEntityId changes needed.');
}

List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();
for (QuoteLineItem qli : [
    SELECT Id, Quote.Name, Product2.Name, TaxTreatmentId
    FROM QuoteLineItem
    WHERE QuoteId IN :demoQuoteIds
]) {
    System.debug(
        'QLI before: ' + qli.Quote.Name +
        ' / ' + qli.Product2.Name +
        ' TaxTreatmentId=' + qli.TaxTreatmentId
    );

    if (qli.TaxTreatmentId != vatTreatmentId) {
        qlisToUpdate.add(new QuoteLineItem(Id = qli.Id, TaxTreatmentId = vatTreatmentId));
    }
}

if (!qlisToUpdate.isEmpty()) {
    update qlisToUpdate;
    System.debug('Updated QLI TaxTreatmentId count=' + qlisToUpdate.size());
} else {
    System.debug('No QLI TaxTreatmentId changes needed.');
}

for (QuoteLineItem qli : [
    SELECT Id, Quote.Name, Product2.Name, TaxTreatmentId, TotalTaxAmount
    FROM QuoteLineItem
    WHERE QuoteId IN :demoQuoteIds
    ORDER BY Quote.Name, Product2.Name
]) {
    System.debug(
        'QLI after: ' + qli.Quote.Name +
        ' / ' + qli.Product2.Name +
        ' TaxTreatmentId=' + qli.TaxTreatmentId +
        ' TotalTaxAmount=' + qli.TotalTaxAmount
    );
}
