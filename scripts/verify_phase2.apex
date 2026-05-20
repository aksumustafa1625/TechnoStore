Order o = [SELECT Id, OrderNumber, Status, SAP_Sales_Order_Number__c, Status_In_SAP__c
           FROM Order WHERE Id = '801aj00002rgb5IAAQ'];
System.debug('=== PHASE 2 VERIFY ===');
System.debug('  OrderNumber             = ' + o.OrderNumber);
System.debug('  Status                  = ' + o.Status);
System.debug('  SAP_Sales_Order_Number__c = ' + o.SAP_Sales_Order_Number__c);
System.debug('  Status_In_SAP__c        = ' + o.Status_In_SAP__c);
if (o.SAP_Sales_Order_Number__c != null) {
    System.debug('>>> PHASE 2 SUCCESS — SAP returned SO number: ' + o.SAP_Sales_Order_Number__c);
} else if (o.Status_In_SAP__c == 'Push Failed') {
    System.debug('>>> PHASE 2 PARTIAL — call made but SAP errored. Status_In_SAP__c=' + o.Status_In_SAP__c);
} else {
    System.debug('Still pending or @future not yet executed. Re-run in a few seconds.');
}
