// Direct test of SapSalesOrderService.pushOrders against an already-Activated Order.
// Bypasses the Order activation transaction (which trips on demo Orders lacking RLM repricing).
List<Order> activated = [SELECT Id, OrderNumber, SAP_Sales_Order_Number__c FROM Order WHERE Status = 'Activated' AND SAP_Sales_Order_Number__c = null ORDER BY CreatedDate DESC LIMIT 1];
if (activated.isEmpty()) {
    System.debug('No Activated Order without SAP_SO — falling back to any Activated Order, will overwrite');
    activated = [SELECT Id, OrderNumber, SAP_Sales_Order_Number__c FROM Order WHERE Status = 'Activated' ORDER BY CreatedDate DESC LIMIT 1];
    if (!activated.isEmpty()) {
        // Reset SO so the push is not skipped by the idempotency check
        Order reset = new Order(Id = activated[0].Id, SAP_Sales_Order_Number__c = null, Status_In_SAP__c = 'Not Yet Pushed');
        update reset;
        System.debug('Reset SAP fields on ' + activated[0].OrderNumber + ' to allow re-push');
    }
}
if (activated.isEmpty()) { System.debug('No Activated Order at all — abort'); return; }
Order o = activated[0];
System.debug('Pushing ' + o.OrderNumber + ' (' + o.Id + ') to SAP SD');

SapSalesOrderService.pushOrders(new Set<Id>{ o.Id });
System.debug('pushOrders called — @future async, runs in next slot. Re-query in ~15s.');
System.debug('Order Id for verify: ' + o.Id);
