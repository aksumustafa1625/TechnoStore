// Phase 2 — directly call SapSalesOrderService.pushOrders to exercise the SAP API call.
// pushOrders is @future(callout=true), so it runs in a separate transaction.
// We can call it on any Order regardless of activation status — the SAP call is what matters.

List<Order> orders = [SELECT Id, OrderNumber, Status, SAP_Sales_Order_Number__c, Status_In_SAP__c
                      FROM Order ORDER BY CreatedDate DESC LIMIT 1];
if (orders.isEmpty()) { System.debug('No Orders — abort'); return; }
Order o = orders[0];
System.debug('Test order: ' + o.OrderNumber + ' Status=' + o.Status);

// Reset SAP fields to allow re-push (idempotency bypass for testing)
o.SAP_Sales_Order_Number__c = null;
o.Status_In_SAP__c = 'Not Yet Pushed';
update o;
System.debug('Reset SAP fields, calling pushOrders async...');

SapSalesOrderService.pushOrders(new Set<Id>{ o.Id });
System.debug('>>> pushOrders enqueued (@future async). Wait 10-15s then check Order audit fields.');
System.debug('>>> Order Id: ' + o.Id);
