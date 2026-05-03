// Step 1: Try to make the tax engine fire on Quote
// 1) Set Product2.TaxPolicyId on the 3 products in the Hamburg quote
// 2) (TaxPolicy.TreatmentSelection change handled separately via PATCH)

Id hamburgQuoteId = '0Q0aj000002IHajCAG';
Id taxPolicyId = '1Tpaj000000IKTJCA4'; // "Tax Policy for LE"

// Get unique Product2Ids from the quote
Set<Id> productIds = new Set<Id>();
for (QuoteLineItem qli : [SELECT Product2Id FROM QuoteLineItem WHERE QuoteId = :hamburgQuoteId]) {
    if (qli.Product2Id != null) productIds.add(qli.Product2Id);
}
System.debug('Distinct products on quote: ' + productIds.size());

// Update each Product2 with TaxPolicyId
List<Product2> productsToUpdate = new List<Product2>();
for (Id pid : productIds) productsToUpdate.add(new Product2(Id = pid, TaxPolicyId = taxPolicyId));
update productsToUpdate;
System.debug('Products updated with TaxPolicyId: ' + productsToUpdate.size());

// Verify
for (Product2 p : [SELECT Id, Name, TaxPolicyId FROM Product2 WHERE Id IN :productIds]) {
    System.debug('Product: ' + p.Name + ' -> TaxPolicy: ' + p.TaxPolicyId);
}

// Now touch QLIs to force re-evaluation
List<QuoteLineItem> qlis = [SELECT Id, Quantity FROM QuoteLineItem WHERE QuoteId = :hamburgQuoteId];
update qlis;
System.debug('QLIs touched: ' + qlis.size());

// Check tax state immediately after
for (QuoteLineItem q : [SELECT Id, Product2.Name, TotalTaxAmount, TaxTreatmentId FROM QuoteLineItem WHERE QuoteId = :hamburgQuoteId]) {
    System.debug('After: ' + q.Product2.Name + ' Tax=' + q.TotalTaxAmount + ' Treatment=' + q.TaxTreatmentId);
}
