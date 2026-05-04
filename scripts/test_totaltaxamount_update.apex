// Test if Quote.TotalTaxAmount is actually updateable
try {
    update new Quote(Id='0Q0aj000002IHajCAG', TotalTaxAmount=489.34);
    System.debug('SUCCESS: TotalTaxAmount updated');
    Quote q = [SELECT TotalTaxAmount, TotalPriceWithTax FROM Quote WHERE Id='0Q0aj000002IHajCAG'];
    System.debug('Verify: TotalTaxAmount=' + q.TotalTaxAmount + ' TotalPriceWithTax=' + q.TotalPriceWithTax);
} catch (Exception e) {
    System.debug('FAILED: ' + e.getTypeName() + ': ' + e.getMessage());
}
