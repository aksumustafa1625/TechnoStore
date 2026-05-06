/**
 * Consumes Inventory_Status_Update__e platform events and updates the related Order in system
 * context. This indirection is needed because the public REST callback endpoint runs as the
 * Site Guest User, which deliberately has no direct edit permission on Order — the platform
 * event publish (allowed for guest users) crosses the trust boundary safely.
 */
public with sharing class InventoryStatusUpdateTriggerHandler {

    public static void handleAfterInsert(List<Inventory_Status_Update__e> events) {
        if (events == null || events.isEmpty()) return;

        Map<Id, Inventory_Status_Update__e> latestEventByOrder = new Map<Id, Inventory_Status_Update__e>();
        for (Inventory_Status_Update__e e : events) {
            if (String.isBlank(e.Order_Id__c) || String.isBlank(e.New_Status__c)) continue;
            try {
                Id orderId = (Id) e.Order_Id__c;
                latestEventByOrder.put(orderId, e); // last write wins if multiple updates for same order
            } catch (Exception ex) {
                System.debug('Skipping event with invalid Order_Id__c: ' + e.Order_Id__c);
            }
        }
        if (latestEventByOrder.isEmpty()) return;

        Datetime now = System.now();
        List<Order> updates = new List<Order>();
        for (Id orderId : latestEventByOrder.keySet()) {
            Inventory_Status_Update__e e = latestEventByOrder.get(orderId);
            updates.add(new Order(
                Id = orderId,
                Inventory_Status__c = e.New_Status__c,
                Inventory_Confirmed_By__c = e.Confirmed_By__c,
                Inventory_Confirmed_At__c = now
            ));
        }
        update updates;
    }
}
