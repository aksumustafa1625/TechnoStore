Order o = [SELECT Id, OrderNumber, Status, Status_In_SAP__c, SAP_Sales_Order_Number__c FROM Order WHERE OrderNumber = '00000170' LIMIT 1];
System.debug('Order ' + o.OrderNumber + ':');
System.debug('  Status                 = ' + o.Status);
System.debug('  Status_In_SAP__c       = ' + o.Status_In_SAP__c);
System.debug('  SAP_Sales_Order_Number = ' + o.SAP_Sales_Order_Number__c);

System.debug('Recent Integration_Error__c rows (any source):');
for (Integration_Error__c ie : [SELECT Name, CreatedDate FROM Integration_Error__c ORDER BY CreatedDate DESC LIMIT 5]) {
    System.debug('  ' + ie.CreatedDate + ' | ' + ie.Name);
}
