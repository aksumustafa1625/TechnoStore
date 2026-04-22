// Test: Add a Laptop product to Test Quote 13 using our custom service
String quoteId = '0Q0aj0000028XorCAE'; // Test Quote 13
String laptopProductId = '01taj00000QnnlQAAR'; // EduBook Basic 11

// Call our service
QuoteProductService.AddToQuoteInput input = new QuoteProductService.AddToQuoteInput();
input.quoteId = quoteId;
input.productId = laptopProductId;
input.quantity = 1;

List<QuoteProductService.AddToQuoteOutput> outputs = QuoteProductService.addProductToQuote(
    new List<QuoteProductService.AddToQuoteInput>{ input }
);

QuoteProductService.AddToQuoteOutput result = outputs[0];
System.debug('=== Result: success=' + result.success + ', message=' + result.message + ', QLI=' + result.quoteLineItemId);

// Verify
if (result.success) {
    QuoteLineItem qli = [SELECT Id, Product2.Name, UnitPrice, Quantity, TotalPrice FROM QuoteLineItem WHERE Id = :result.quoteLineItemId];
    System.debug('=== QuoteLineItem: ' + qli.Product2.Name + ' | Price=$' + qli.UnitPrice + ' | Qty=' + qli.Quantity + ' | Total=$' + qli.TotalPrice);
}
