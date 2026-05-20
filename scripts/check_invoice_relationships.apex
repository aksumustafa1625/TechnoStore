// Verify BillingAccount relationship + InvoiceLine availability for refactor
System.debug('=== Invoice + BillingAccount ===');
for (Invoice inv : [
    SELECT Id, DocumentNumber, Status, TotalAmount, TotalAmountWithTax, InvoiceDate,
           BillingAccountId, BillingAccount.Name,
           BillingAccount.BillingStreet, BillingAccount.BillingCity,
           BillingAccount.BillingPostalCode, BillingAccount.BillingCountry,
           SAP_Tax_Amount__c, Tax_Engine_Used__c
    FROM Invoice ORDER BY CreatedDate DESC LIMIT 3
]) {
    System.debug('  ' + inv.DocumentNumber + ' | Status=' + inv.Status
        + ' | Total=' + inv.TotalAmount + ' | WithTax=' + inv.TotalAmountWithTax
        + ' | Acct=' + inv.BillingAccount.Name
        + ' | City=' + inv.BillingAccount.BillingCity
        + ' | Country=' + inv.BillingAccount.BillingCountry
        + ' | Date=' + inv.InvoiceDate);
}

System.debug('=== InvoiceLine ===');
try {
    Integer c = Database.countQuery('SELECT COUNT() FROM InvoiceLine');
    System.debug('  InvoiceLine count: ' + c);
    List<String> ilNames = new List<String>(InvoiceLine.SObjectType.getDescribe().fields.getMap().keySet());
    ilNames.sort();
    System.debug('  InvoiceLine fields: ' + String.join(ilNames, ', '));
} catch (Exception e) {
    System.debug('  InvoiceLine error: ' + e.getMessage());
}
