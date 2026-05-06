/**
 * Invocable used by the Mark In Stock / Mark Out of Stock quick actions on Order. Updates
 * Inventory_Status__c plus the audit fields (Inventory_Confirmed_By__c with the running
 * user's full name, Inventory_Confirmed_At__c with the current timestamp).
 *
 * Encapsulating this in Apex avoids the brittle $User/$Flow reference path in flow XML —
 * UserInfo.getName() and System.now() are always available in Apex regardless of flow context.
 */
public with sharing class InventoryDecisionService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
        @InvocableVariable(required=true label='New Status' description='Either "In Stock" or "Out of Stock"')
        public String newStatus;
    }

    @InvocableMethod(label='Mark Order Inventory Status' description='Updates the Order inventory status and stamps the running user + timestamp.')
    public static void markStatus(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;

        Datetime now = System.now();
        String userName = UserInfo.getName();

        List<Order> updates = new List<Order>();
        for (Request r : requests) {
            if (r.orderId == null || String.isBlank(r.newStatus)) continue;
            updates.add(new Order(
                Id = r.orderId,
                Inventory_Status__c = r.newStatus,
                Inventory_Confirmed_By__c = userName,
                Inventory_Confirmed_At__c = now
            ));
        }
        if (!updates.isEmpty()) update updates;
    }
}
