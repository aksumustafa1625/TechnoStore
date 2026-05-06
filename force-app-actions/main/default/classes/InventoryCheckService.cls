/**
 * Initiates a warehouse inventory check by:
 *   1. Publishing an Inventory_Check_Requested__e platform event so MuleSoft can fire a
 *      Slack notification to the #warehouse channel.
 *   2. Submitting the Order to the Inventory_Approval approval process. The initial
 *      submission action sets Inventory_Status__c to "Pending Check" and locks the record
 *      from edit (AdminOnly editability), so the sales rep cannot bypass the warehouse step.
 *
 * The warehouse user later clicks Approve or Reject on the order's standard approval
 * banner — final approval flips Inventory_Status__c to "In Stock", final rejection flips
 * it to "Out of Stock". Both transitions are workflow field updates wired into the
 * approval process; no Mark In Stock / Mark Out of Stock quick actions on the layout.
 */
public with sharing class InventoryCheckService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Result {
        @InvocableVariable(label='Status message')
        public String statusMessage;
    }

    @InvocableMethod(label='Request Inventory Check' description='Publishes the Slack notification event and submits the Order to the Inventory_Approval approval process.')
    public static List<Result> requestCheck(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> orderIds = new Set<Id>();
        for (Request r : requests) if (r.orderId != null) orderIds.add(r.orderId);
        if (orderIds.isEmpty()) return results;

        Map<Id, Order> orderById = new Map<Id, Order>([
            SELECT Id, OrderNumber, TotalAmount, Account.Name,
                   (SELECT Id, Product2.Name, Quantity FROM OrderItems)
            FROM Order
            WHERE Id IN :orderIds
        ]);

        String orgBaseUrl = URL.getOrgDomainUrl().toExternalForm();

        // Step 1: build + publish the event for the Slack notification
        List<Inventory_Check_Requested__e> events = new List<Inventory_Check_Requested__e>();
        for (Request r : requests) {
            Order o = orderById.get(r.orderId);
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

        // Step 2: submit each Order to the Inventory_Approval approval process. The initial
        // submission action sets Inventory_Status__c='Pending Check' and locks the record.
        for (Request r : requests) {
            Result res = new Result();
            Order o = orderById.get(r.orderId);
            if (o == null) {
                res.statusMessage = 'Order not found: ' + r.orderId;
                results.add(res);
                continue;
            }
            try {
                Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
                submit.setObjectId(o.Id);
                submit.setProcessDefinitionNameOrId('Inventory_Approval');
                submit.setComments('Inventory check requested via the Order quick action.');
                Approval.ProcessResult submitResult = Approval.process(submit);

                if (submitResult.isSuccess()) {
                    res.statusMessage = 'Order submitted to warehouse for approval. Slack #warehouse notification sent.';
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
