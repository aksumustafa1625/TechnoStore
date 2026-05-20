// HONEST ROLLBACK: Clear the manually-set SAP_Sales_Order_Number__c
// because that field should ONLY be populated by a real API response,
// not by hand. This preserves demo integrity.

Order o = [
    SELECT Id, OrderNumber, SAP_Sales_Order_Number__c, Status_In_SAP__c
    FROM Order WHERE Id = '801aj00002rgb5IAAQ'
];
System.debug('=== BEFORE ROLLBACK ===');
System.debug('  OrderNumber:               ' + o.OrderNumber);
System.debug('  SAP_Sales_Order_Number__c: ' + o.SAP_Sales_Order_Number__c);
System.debug('  Status_In_SAP__c:          ' + o.Status_In_SAP__c);

// Restore to honest state: keep "Push Failed" status (real result from sandbox POST)
// Clear the manually-assigned SO number
o.SAP_Sales_Order_Number__c = null;
o.Status_In_SAP__c = 'Push Failed';  // <- real result from earlier smoke test
update o;

Order verify = [
    SELECT Id, OrderNumber, SAP_Sales_Order_Number__c, Status_In_SAP__c
    FROM Order WHERE Id = :o.Id
];
System.debug('=== AFTER ROLLBACK ===');
System.debug('  SAP_Sales_Order_Number__c: ' + verify.SAP_Sales_Order_Number__c);
System.debug('  Status_In_SAP__c:          ' + verify.Status_In_SAP__c);
System.debug('');
System.debug('>>> HONEST STATE RESTORED.');
System.debug('>>> SF Order ' + verify.OrderNumber + ' reflects ACTUAL sandbox response (Push Failed).');
System.debug('>>> Trial Fiori SO 325734 remains as sample/reference only.');
