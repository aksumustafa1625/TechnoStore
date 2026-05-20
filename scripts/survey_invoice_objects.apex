// Decide which invoice object to use for lexoffice/DATEV: count records + show sample
System.debug('=== Demo_Invoice__c ===');
Integer demoCount = Database.countQuery('SELECT COUNT() FROM Demo_Invoice__c');
System.debug('Record count: ' + demoCount);
for (Demo_Invoice__c di : [
    SELECT Name, Status__c, Total_Amount__c, Account__r.Name, Order__r.OrderNumber,
           Invoice_Date__c, Customer_Email__c
    FROM Demo_Invoice__c ORDER BY CreatedDate DESC LIMIT 5
]) {
    System.debug('  ' + di.Name + ' | Status=' + di.Status__c + ' | Total=' + di.Total_Amount__c
        + ' | Acct=' + di.Account__r.Name + ' | Order=' + di.Order__r.OrderNumber
        + ' | Date=' + di.Invoice_Date__c);
}

System.debug('=== Standard Invoice (Industries Billing) ===');
try {
    Integer invCount = Database.countQuery('SELECT COUNT() FROM Invoice');
    System.debug('Record count: ' + invCount);
    for (Invoice inv : [
        SELECT DocumentNumber, Status, TotalAmount, BillToContactId,
               SAP_Tax_Amount__c, SAP_Tax_Rate__c, Tax_Engine_Used__c, Payment_Method__c
        FROM Invoice ORDER BY CreatedDate DESC LIMIT 5
    ]) {
        System.debug('  ' + inv.DocumentNumber + ' | Status=' + inv.Status + ' | Total=' + inv.TotalAmount
            + ' | Tax=' + inv.SAP_Tax_Amount__c + ' | Engine=' + inv.Tax_Engine_Used__c);
    }
} catch (Exception e) {
    System.debug('Standard Invoice query failed: ' + e.getMessage());
}
