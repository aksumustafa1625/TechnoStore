/**
 * Initiates a warehouse inventory check using the SAP-first / JIRA-fallback hybrid pattern
 * (see ADR-022).
 *
 *   1. CALLOUT phase — `SapMaterialStockService.checkOrderStock` queries SAP MM
 *      API_MATERIAL_STOCK_SRV for real-time ATP for each Order's primary product.
 *      The service writes SAP_Available_Quantity__c + SAP_Inventory_Checked_At__c back
 *      to the Order so dashboards and audit reports can see SAP state at decision time.
 *
 *   2. DECISION phase — for each Order:
 *      - If SAP reports >= total order quantity, auto-activate: set Inventory_Status__c =
 *        'In Stock', Status = 'Activated', Inventory_Confirmed_By__c = 'SAP MM'.
 *        OrderTriggerHandler.afterUpdate then mints Assets per OrderItem (Pattern 1).
 *        No human warehouse approval needed; deal closes ~3 seconds end-to-end.
 *      - Else (SAP says insufficient, returns null, or callout fails): fall back to the
 *        legacy warehouse approval path — publish Inventory_Check_Requested__e platform
 *        event for Slack notification, submit Order to Inventory_Approval process. From
 *        there it's VF approve → activate (Path 1, ADR-011) or VF reject → JIRA ticket
 *        → warehouse Done → JIRA webhook → activate (Path 2, ADR-011).
 *
 * Convergence: every path ends at Order.Status = 'Activated'. Sales rep doesn't see or
 * care which path fired. SAP visibility (SAP_Available_Quantity__c, SAP_Inventory_Checked_At__c)
 * is preserved on the Order regardless of which path activates it, so the audit trail
 * always carries the SAP state at decision time.
 *
 * Production note (ADR-015): the direct Apex callout to SAP would migrate behind MuleSoft
 * for retry / DLQ / transformation. The Apex contract — query, returns ATP — stays the same.
 */
public with sharing class InventoryCheckService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Result {
        @InvocableVariable(label='Status message')
        public String statusMessage;
        @InvocableVariable(label='Path Taken')
        public String pathTaken;   // SAP_AUTO_ACTIVATE | WAREHOUSE_APPROVAL
        @InvocableVariable(label='SAP Available Quantity')
        public Decimal sapAvailableQuantity;
    }

    @InvocableMethod(label='Request Inventory Check' description='SAP-first ATP query. Auto-activates Order if SAP confirms sufficient stock; falls back to warehouse approval (Slack + JIRA) otherwise.')
    public static List<Result> requestCheck(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> orderIds = new Set<Id>();
        for (Request r : requests) if (r.orderId != null) orderIds.add(r.orderId);
        if (orderIds.isEmpty()) return results;

        // Sum OrderItem quantities per Order — used to compare SAP available qty against requested qty.
        Map<Id, Decimal> requestedQtyByOrder = new Map<Id, Decimal>();
        for (OrderItem oi : [SELECT OrderId, Quantity FROM OrderItem WHERE OrderId IN :orderIds]) {
            Decimal q = (oi.Quantity == null) ? 0 : oi.Quantity;
            Decimal existing = requestedQtyByOrder.containsKey(oi.OrderId) ? requestedQtyByOrder.get(oi.OrderId) : 0;
            requestedQtyByOrder.put(oi.OrderId, existing + q);
        }

        // CALLOUT phase: SAP MM ATP query for all Orders in one batch.
        // SapMaterialStockService writes SAP_Available_Quantity__c back to each Order internally.
        Map<Id, Decimal> sapAvailableByOrder = new Map<Id, Decimal>();
        List<SapMaterialStockService.Request> sapReqs = new List<SapMaterialStockService.Request>();
        for (Id oid : orderIds) {
            SapMaterialStockService.Request sr = new SapMaterialStockService.Request();
            sr.orderId = oid;
            sapReqs.add(sr);
        }
        try {
            List<SapMaterialStockService.Result> sapResults = SapMaterialStockService.checkOrderStock(sapReqs);
            for (SapMaterialStockService.Result sr : sapResults) {
                if (sr.status == 'Success' && sr.availableQuantity != null) {
                    sapAvailableByOrder.put(sr.orderId, sr.availableQuantity);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SAP MM pre-check failed; all orders will fall back to warehouse approval: ' + e.getMessage());
        }

        // DECISION phase: split orders into auto-activate (SAP confirmed) vs warehouse-approval (fallback).
        Set<Id> autoActivateOrderIds = new Set<Id>();
        Set<Id> warehouseOrderIds = new Set<Id>();
        for (Id oid : orderIds) {
            Decimal requested = requestedQtyByOrder.containsKey(oid) ? requestedQtyByOrder.get(oid) : 0;
            Decimal sapAvail = sapAvailableByOrder.get(oid);
            if (sapAvail != null && requested > 0 && sapAvail >= requested) {
                autoActivateOrderIds.add(oid);
            } else {
                warehouseOrderIds.add(oid);
            }
        }

        Datetime now = System.now();

        // Auto-activate path: directly flip Inventory_Status__c + Status. OrderTrigger picks
        // up the Status transition and mints Assets per Pattern 1 (ADR-012).
        if (!autoActivateOrderIds.isEmpty()) {
            List<Order> activations = new List<Order>();
            for (Id oid : autoActivateOrderIds) {
                activations.add(new Order(
                    Id = oid,
                    Inventory_Status__c = 'In Stock',
                    Inventory_Confirmed_By__c = 'SAP MM',
                    Inventory_Confirmed_At__c = now,
                    Status = 'Activated'
                ));
            }
            Database.SaveResult[] saveRes = Database.update(activations, false);
            for (Integer i = 0; i < saveRes.size(); i++) {
                Result res = new Result();
                res.pathTaken = 'SAP_AUTO_ACTIVATE';
                res.sapAvailableQuantity = sapAvailableByOrder.get(activations[i].Id);
                if (saveRes[i].isSuccess()) {
                    res.statusMessage = 'SAP confirmed sufficient stock (qty=' + res.sapAvailableQuantity + '); Order auto-activated. No warehouse approval needed.';
                } else {
                    res.statusMessage = 'SAP confirmed stock but auto-activation failed: ' + saveRes[i].getErrors()[0].getMessage() + '. Falling back to warehouse approval.';
                    warehouseOrderIds.add(activations[i].Id);   // retry via warehouse path
                }
                results.add(res);
            }
        }

        // Warehouse approval path (legacy, ADR-011): Slack notification + Inventory_Approval submit.
        if (!warehouseOrderIds.isEmpty()) {
            Map<Id, Order> orderById = new Map<Id, Order>([
                SELECT Id, OrderNumber, TotalAmount, Account.Name,
                       (SELECT Id, Product2.Name, Quantity FROM OrderItems)
                FROM Order
                WHERE Id IN :warehouseOrderIds
            ]);

            String orgBaseUrl = URL.getOrgDomainUrl().toExternalForm();
            List<Inventory_Check_Requested__e> events = new List<Inventory_Check_Requested__e>();
            for (Id oid : warehouseOrderIds) {
                Order o = orderById.get(oid);
                if (o == null) continue;
                events.add(new Inventory_Check_Requested__e(
                    Order_Id__c       = o.Id,
                    Order_Number__c   = o.OrderNumber,
                    Account_Name__c   = (o.Account != null) ? o.Account.Name : '(no account)',
                    Total_Amount__c   = o.TotalAmount,
                    Item_Count__c     = (o.OrderItems == null) ? 0 : o.OrderItems.size(),
                    Items_Summary__c  = buildItemsSummary(o.OrderItems),
                    Order_Url__c      = orgBaseUrl + '/apex/WarehouseInventoryApproval?orderId=' + o.Id
                ));
            }
            if (!events.isEmpty()) EventBus.publish(events);

            for (Id oid : warehouseOrderIds) {
                Result res = new Result();
                res.pathTaken = 'WAREHOUSE_APPROVAL';
                res.sapAvailableQuantity = sapAvailableByOrder.get(oid);
                Order o = orderById.get(oid);
                if (o == null) {
                    res.statusMessage = 'Order not found: ' + oid;
                    results.add(res);
                    continue;
                }
                String sapNote = (res.sapAvailableQuantity == null)
                    ? 'SAP MM had no ATP data for this Order.'
                    : 'SAP reported only ' + res.sapAvailableQuantity + ' units available; requested qty exceeds.';
                try {
                    Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
                    submit.setObjectId(o.Id);
                    submit.setProcessDefinitionNameOrId('Inventory_Approval');
                    submit.setComments(sapNote + ' Routed to warehouse for manual confirmation.');
                    Approval.ProcessResult submitResult = Approval.process(submit);
                    if (submitResult.isSuccess()) {
                        res.statusMessage = 'Routed to warehouse approval. ' + sapNote + ' Slack #warehouse notification sent.';
                    } else {
                        String msgs = '';
                        for (Database.Error err : submitResult.getErrors()) {
                            if (msgs.length() > 0) msgs += '; ';
                            msgs += err.getMessage();
                        }
                        res.statusMessage = 'Approval submission failed: ' + msgs;
                    }
                } catch (Exception e) {
                    res.statusMessage = 'Approval submission error: ' + e.getMessage();
                }
                results.add(res);
            }
        }

        return results;
    }

    private static String buildItemsSummary(List<OrderItem> items) {
        if (items == null || items.isEmpty()) return '';
        List<String> parts = new List<String>();
        for (OrderItem oi : items) {
            String productName = (oi.Product2 != null && oi.Product2.Name != null) ? oi.Product2.Name : '(unknown)';
            Integer qty = (oi.Quantity == null) ? 1 : Integer.valueOf(oi.Quantity);
            parts.add(productName + ' (qty ' + qty + ')');
        }
        return String.join(parts, '; ');
    }
}
