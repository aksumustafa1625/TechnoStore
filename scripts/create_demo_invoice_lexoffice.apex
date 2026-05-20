// Create a demo Demo_Invoice__c linked to Order 00000170 (Main Capital IT-Partners GmbH, Frankfurt)
// for the lexoffice + DATEV demo.
List<Order> orders = [
    SELECT Id, OrderNumber, AccountId, Account.Name, TotalAmount
    FROM Order WHERE OrderNumber = '00000170' LIMIT 1
];
if (orders.isEmpty()) { System.debug('Order 00000170 not found'); return; }
Order o = orders[0];

// Avoid duplicates
List<Demo_Invoice__c> existing = [SELECT Id, Name FROM Demo_Invoice__c WHERE Order__c = :o.Id LIMIT 1];
Demo_Invoice__c inv;
if (!existing.isEmpty()) {
    inv = existing[0];
    System.debug('Reusing existing Demo_Invoice__c: ' + inv.Name);
} else {
    inv = new Demo_Invoice__c(
        Account__c = o.AccountId,
        Order__c = o.Id,
        Total_Amount__c = o.TotalAmount,
        Status__c = 'Paid',
        Invoice_Date__c = Date.today(),
        Due_Date__c = Date.today().addDays(14),
        Paid_Date__c = Date.today(),
        Customer_Email__c = 'demo-user@example.com'
    );
    insert inv;
    System.debug('Created Demo_Invoice__c: ' + inv.Id);
}

Demo_Invoice__c check = [
    SELECT Id, Name, Status__c, Total_Amount__c, Account__r.Name, Order__r.OrderNumber
    FROM Demo_Invoice__c WHERE Id = :inv.Id
];
System.debug('=== DEMO INVOICE READY ===');
System.debug('  Name: ' + check.Name);
System.debug('  Id: ' + check.Id);
System.debug('  Account: ' + check.Account__r.Name);
System.debug('  Order: ' + check.Order__r.OrderNumber);
System.debug('  Total: ' + check.Total_Amount__c);
System.debug('  Status: ' + check.Status__c);
System.debug('>>> Use this Id for lexoffice publish test: ' + check.Id);
