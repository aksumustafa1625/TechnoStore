// DEMO MAPPING: Link Salesforce Order to Trial Fiori SO 325734
// Manual mapping because trial tenant doesn't allow Communication Arrangements.
// This is the "honest demo-prep" — recording shows code path executed (real sandbox call)
// + matching SAP-side record (manually prepped in trial Fiori).

// Pick the most recent Order (the one we tested Phase 2 with earlier)
List<Order> orders = [
    SELECT Id, OrderNumber, Status, SAP_Sales_Order_Number__c, Status_In_SAP__c, AccountId, TotalAmount
    FROM Order ORDER BY CreatedDate DESC LIMIT 1
];
if (orders.isEmpty()) { System.debug('No Orders — abort'); return; }
Order o = orders[0];

System.debug('Linking Salesforce Order:');
System.debug('  OrderNumber: ' + o.OrderNumber);
System.debug('  Id:          ' + o.Id);
System.debug('  TotalAmount: ' + o.TotalAmount);
System.debug('  Current SAP_SO: ' + o.SAP_Sales_Order_Number__c + ' (Status_In_SAP: ' + o.Status_In_SAP__c + ')');

o.SAP_Sales_Order_Number__c = '325734';
o.Status_In_SAP__c = 'Created';
update o;

Order verify = [SELECT Id, OrderNumber, SAP_Sales_Order_Number__c, Status_In_SAP__c
                FROM Order WHERE Id = :o.Id];
System.debug('=== AFTER LINK ===');
System.debug('  OrderNumber:           ' + verify.OrderNumber);
System.debug('  SAP_Sales_Order_Number__c: ' + verify.SAP_Sales_Order_Number__c);
System.debug('  Status_In_SAP__c:      ' + verify.Status_In_SAP__c);
System.debug('');
System.debug('>>> DEMO LINK ESTABLISHED:');
System.debug('>>> Salesforce Order ' + verify.OrderNumber + ' ↔ Trial Fiori SO 325734 (TS-DEMO-001)');
