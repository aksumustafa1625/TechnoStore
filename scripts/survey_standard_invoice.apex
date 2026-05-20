// Inspect standard Invoice + InvoiceLine schema and a sample record for lexoffice/DATEV refactor.
System.debug('=== Invoice fields (subset) ===');
Map<String, Schema.SObjectField> invFields = Invoice.SObjectType.getDescribe().fields.getMap();
for (String f : new List<String>{'documentnumber','totalamount','grandtotalamount','nettotalamount','taxtotalamount',
        'billtoaccountid','billtocontactid','invoicedate','duedate','status','currencyisocode'}) {
    System.debug('  ' + f + ' exists=' + invFields.containsKey(f));
}

System.debug('=== Sample Invoice DOC-000000001 ===');
for (Invoice inv : [
    SELECT Id, DocumentNumber, TotalAmount, Status, InvoiceDate, DueDate,
           BillToAccountId, BillToAccount.Name,
           BillToAccount.BillingStreet, BillToAccount.BillingCity,
           BillToAccount.BillingPostalCode, BillToAccount.BillingCountry,
           SAP_Tax_Amount__c, SAP_Tax_Rate__c, Tax_Engine_Used__c
    FROM Invoice ORDER BY CreatedDate DESC LIMIT 3
]) {
    System.debug('  ' + inv.DocumentNumber + ' | Total=' + inv.TotalAmount + ' | Status=' + inv.Status
        + ' | Acct=' + inv.BillToAccount.Name + ' | Date=' + inv.InvoiceDate
        + ' | Tax=' + inv.SAP_Tax_Amount__c + ' | City=' + inv.BillToAccount.BillingCity);
}

System.debug('=== InvoiceLine schema check ===');
try {
    Map<String, Schema.SObjectField> ilFields = InvoiceLine.SObjectType.getDescribe().fields.getMap();
    for (String f : new List<String>{'invoiceid','product2id','quantity','rate','unitprice','amount',
            'chargeamount','description','linenumber'}) {
        System.debug('  InvoiceLine.' + f + ' exists=' + ilFields.containsKey(f));
    }
    System.debug('  --- sample InvoiceLines ---');
    for (InvoiceLine il : [SELECT Id, InvoiceId, Description FROM InvoiceLine LIMIT 5]) {
        System.debug('    ' + il.Id + ' | Inv=' + il.InvoiceId + ' | Desc=' + il.Description);
    }
} catch (Exception e) {
    System.debug('  InvoiceLine not accessible: ' + e.getMessage());
}
