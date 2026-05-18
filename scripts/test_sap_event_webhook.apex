// Phase 7 end-to-end test — feed 4 synthetic CloudEvents (one per route) directly
// to the dispatcher and verify each route lands. Bypasses HTTP layer because demo
// runs from Apex; full HTTP path is exercised via Postman POST to /services/apexrest/sap/event.

// First we need test targets — pick existing records that have the SAP join keys set.
List<Order> orderWithSap = [SELECT Id, OrderNumber, SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE SAP_Sales_Order_Number__c != null LIMIT 1];
List<Account> acctWithSap = [SELECT Id, Name, SAP_BP_Number__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c FROM Account WHERE SAP_BP_Number__c != null LIMIT 1];
List<Product2> prodWithSap = [SELECT Id, Name, SAP_Material_Number__c, SAP_Product_Description__c, SAP_Last_Synced_At__c FROM Product2 WHERE SAP_Material_Number__c != null LIMIT 1];
List<Invoice> invWithRef = [SELECT Id, DocumentNumber, SAP_Payment_Reference__c, SAP_Payment_Posted_At__c FROM Invoice WHERE SAP_Payment_Reference__c != null LIMIT 1];

System.debug('Test targets:');
System.debug('  Order  : ' + (orderWithSap.isEmpty() ? 'none' : orderWithSap[0].OrderNumber + ' (SAP SO=' + orderWithSap[0].SAP_Sales_Order_Number__c + ', Status_In_SAP=' + orderWithSap[0].Status_In_SAP__c + ')'));
System.debug('  Account: ' + (acctWithSap.isEmpty() ? 'none' : acctWithSap[0].Name + ' (BP=' + acctWithSap[0].SAP_BP_Number__c + ', Group=' + acctWithSap[0].SAP_Customer_Group__c + ')'));
System.debug('  Product: ' + (prodWithSap.isEmpty() ? 'none' : prodWithSap[0].Name + ' (Material=' + prodWithSap[0].SAP_Material_Number__c + ', Desc=' + prodWithSap[0].SAP_Product_Description__c + ')'));
System.debug('  Invoice: ' + (invWithRef.isEmpty() ? 'none' : invWithRef[0].DocumentNumber + ' (PaymentRef=' + invWithRef[0].SAP_Payment_Reference__c + ')'));
System.debug('---');

// EVENT 1 — SalesOrder status changed to Complete (C)
if (!orderWithSap.isEmpty()) {
    SapInboundEventDispatcher.CloudEvent e1 = new SapInboundEventDispatcher.CloudEvent();
    e1.eventId = 'evt-test-so-' + System.currentTimeMillis();
    e1.eventType = 'sap.s4.beh.salesorder.v1.SalesOrder.Changed.v1';
    e1.subject = orderWithSap[0].SAP_Sales_Order_Number__c;
    e1.source = '/sap/s4hanacloud';
    e1.data = new Map<String, Object>{ 'SalesOrder' => orderWithSap[0].SAP_Sales_Order_Number__c, 'OverallSDProcessStatus' => 'C' };
    SapInboundEventDispatcher.dispatch(e1);
    System.debug('Dispatched Event 1: SO ' + e1.subject + ' status → Complete');
}

// EVENT 2 — BusinessPartner updated (Group changed BP01 → BP02)
if (!acctWithSap.isEmpty()) {
    SapInboundEventDispatcher.CloudEvent e2 = new SapInboundEventDispatcher.CloudEvent();
    e2.eventId = 'evt-test-bp-' + System.currentTimeMillis();
    e2.eventType = 'sap.s4.beh.businesspartner.v1.BusinessPartner.Changed.v1';
    e2.subject = acctWithSap[0].SAP_BP_Number__c;
    e2.source = '/sap/s4hanacloud';
    e2.data = new Map<String, Object>{ 'BusinessPartner' => acctWithSap[0].SAP_BP_Number__c, 'BusinessPartnerGrouping' => 'BP02' };
    SapInboundEventDispatcher.dispatch(e2);
    System.debug('Dispatched Event 2: BP ' + e2.subject + ' group → BP02');
}

// EVENT 3 — Product description changed
if (!prodWithSap.isEmpty()) {
    SapInboundEventDispatcher.CloudEvent e3 = new SapInboundEventDispatcher.CloudEvent();
    e3.eventId = 'evt-test-prod-' + System.currentTimeMillis();
    e3.eventType = 'sap.s4.beh.product.v1.Product.Changed.v1';
    e3.subject = prodWithSap[0].SAP_Material_Number__c;
    e3.source = '/sap/s4hanacloud';
    e3.data = new Map<String, Object>{ 'Product' => prodWithSap[0].SAP_Material_Number__c, 'ProductDescription' => 'Updated via inbound event ' + System.now().format() };
    SapInboundEventDispatcher.dispatch(e3);
    System.debug('Dispatched Event 3: Product ' + e3.subject + ' description updated');
}

// EVENT 4 — Payment posted (touches Invoice.SAP_Payment_Posted_At__c)
if (!invWithRef.isEmpty()) {
    SapInboundEventDispatcher.CloudEvent e4 = new SapInboundEventDispatcher.CloudEvent();
    e4.eventId = 'evt-test-pay-' + System.currentTimeMillis();
    e4.eventType = 'sap.s4.beh.payment.v1.Payment.Posted.v1';
    e4.subject = invWithRef[0].SAP_Payment_Reference__c;
    e4.source = '/sap/s4hanacloud';
    e4.data = new Map<String, Object>{ 'PaymentReference' => invWithRef[0].SAP_Payment_Reference__c };
    SapInboundEventDispatcher.dispatch(e4);
    System.debug('Dispatched Event 4: Payment ' + e4.subject + ' posted');
}

// Verify side effects
System.debug('---');
System.debug('Side-effect verification:');
if (!orderWithSap.isEmpty()) {
    Order o = [SELECT Id, OrderNumber, Status_In_SAP__c FROM Order WHERE Id = :orderWithSap[0].Id];
    System.debug('  Order ' + o.OrderNumber + ' Status_In_SAP__c = ' + o.Status_In_SAP__c);
}
if (!acctWithSap.isEmpty()) {
    Account a = [SELECT Id, Name, SAP_Customer_Group__c, SAP_Last_Synced_At__c FROM Account WHERE Id = :acctWithSap[0].Id];
    System.debug('  Account ' + a.Name + ' Group=' + a.SAP_Customer_Group__c + ' LastSynced=' + a.SAP_Last_Synced_At__c);
}
if (!prodWithSap.isEmpty()) {
    Product2 p = [SELECT Id, Name, SAP_Product_Description__c, SAP_Last_Synced_At__c FROM Product2 WHERE Id = :prodWithSap[0].Id];
    System.debug('  Product ' + p.Name + ' Desc=' + p.SAP_Product_Description__c + ' LastSynced=' + p.SAP_Last_Synced_At__c);
}
if (!invWithRef.isEmpty()) {
    Invoice i = [SELECT Id, DocumentNumber, SAP_Payment_Posted_At__c FROM Invoice WHERE Id = :invWithRef[0].Id];
    System.debug('  Invoice ' + i.DocumentNumber + ' PostedAt=' + i.SAP_Payment_Posted_At__c);
}
