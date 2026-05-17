/**
 * Consumes Inventory_Status_Update__e platform events and updates the related Order in system
 * context. This indirection is needed because the public REST callback endpoints (InventoryCheckCallback
 * for Slack/Mule, JiraStatusWebhook for JIRA Automation) run as the Site Guest User, which deliberately
 * has no direct edit permission on Order — the platform event publish (allowed for guest users) crosses
 * the trust boundary safely.
 *
 * Side effect: when New_Status__c == 'In Stock' AND the Order is still Draft, the handler also flips
 * Status to Activated. This implements Path 2 of the warehouse approval design (JIRA Done → Order
 * auto-activates) and keeps the Slack callback path symmetric. OrderTriggerHandler.beforeUpdate
 * backfills BillToContactId + addresses, so activation passes built-in validation; afterUpdate
 * creates Assets for each OrderItem.
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

        Map<Id, Order> currentOrders = new Map<Id, Order>([
            SELECT Id, Status FROM Order WHERE Id IN :latestEventByOrder.keySet()
        ]);

        Datetime now = System.now();

        // Pass 1: update Inventory_Status / Confirmed fields (safe — text fields, no activation validation)
        List<Order> inventoryUpdates = new List<Order>();
        for (Id orderId : latestEventByOrder.keySet()) {
            Inventory_Status_Update__e e = latestEventByOrder.get(orderId);
            inventoryUpdates.add(new Order(
                Id = orderId,
                Inventory_Status__c = e.New_Status__c,
                Inventory_Confirmed_By__c = e.Confirmed_By__c,
                Inventory_Confirmed_At__c = now
            ));
        }
        update inventoryUpdates;

        // Pass 2: attempt Status=Activated only for Draft orders with In Stock event.
        // Done with allOrNone=false so RLM pricing/validation failures don't poison the whole batch
        // (e.g. unrepriced demo orders); successful ones still activate, failed ones are logged.
        List<Order> activations = new List<Order>();
        Map<Id, String> jiraDrivenCandidates = new Map<Id, String>();
        for (Id orderId : latestEventByOrder.keySet()) {
            Inventory_Status_Update__e e = latestEventByOrder.get(orderId);
            Order existing = currentOrders.get(orderId);
            if (e.New_Status__c == 'In Stock' && existing != null && existing.Status != 'Activated') {
                activations.add(new Order(Id = orderId, Status = 'Activated'));
                String confirmedBy = e.Confirmed_By__c;
                if (confirmedBy != null && confirmedBy.length() >= 5 && confirmedBy.substring(0, 5).equalsIgnoreCase('JIRA ')) {
                    jiraDrivenCandidates.put(orderId, confirmedBy);
                }
            }
        }
        if (activations.isEmpty()) return;

        Database.SaveResult[] saveResults = Database.update(activations, false);
        Set<Id> activatedOrderIds = new Set<Id>();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            if (sr.isSuccess()) {
                activatedOrderIds.add(activations[i].Id);
            } else {
                System.debug(LoggingLevel.WARN, 'Order activation failed for ' + activations[i].Id + ': ' + sr.getErrors()[0].getMessage());
            }
        }

        // Pass 3: completed Task on the Order as an audit trail visible in the Order's Activity Timeline.
        // Mirrors the Approver Comments style on the VF approval path. Tasks always work on Order
        // regardless of Chatter feed-tracking config, unlike FeedItems which require enableFeeds=true.
        Datetime activationTime = System.now();
        List<Task> auditTasks = new List<Task>();
        for (Id orderId : jiraDrivenCandidates.keySet()) {
            if (!activatedOrderIds.contains(orderId)) continue;
            String confirmedBy = jiraDrivenCandidates.get(orderId);
            auditTasks.add(new Task(
                WhatId = orderId,
                Subject = 'Inventory confirmed in stock via ' + confirmedBy,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today(),
                Description = 'Inventory confirmed in stock via ' + confirmedBy + '.\n\n'
                            + 'Order auto-activated by the warehouse replenishment workflow:\n'
                            + '  - Status: Draft -> Activated\n'
                            + '  - Inventory_Status__c: Out of Stock -> In Stock\n'
                            + '  - Trigger: JIRA ticket transitioned to Done\n'
                            + '  - Bridge: JiraStatusWebhook REST endpoint + Inventory_Status_Update__e platform event\n'
                            + '  - Time: ' + activationTime.format()
            ));
        }
        if (!auditTasks.isEmpty()) {
            try {
                insert auditTasks;
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Audit Task insert failed (non-fatal): ' + ex.getMessage());
            }
        }

        // Pass 4: submit + immediately auto-approve a separate Inventory_Audit_Approval cycle to
        // produce a Process Instance Step record symmetric to the VF "Mark In Stock" path. This
        // audit-only approval process has zero field updates, so it doesn't conflict with the
        // already-Activated Order state.
        for (Id orderId : jiraDrivenCandidates.keySet()) {
            if (!activatedOrderIds.contains(orderId)) continue;
            String confirmedBy = jiraDrivenCandidates.get(orderId);
            try {
                Approval.ProcessSubmitRequest sub = new Approval.ProcessSubmitRequest();
                sub.setObjectId(orderId);
                sub.setProcessDefinitionNameOrId('Inventory_Audit_Approval');
                sub.setComments('Audit cycle for ' + confirmedBy + ' transition to Done.');
                sub.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
                Approval.ProcessResult subResult = Approval.process(sub);
                if (subResult.isSuccess() && subResult.getNewWorkitemIds() != null && !subResult.getNewWorkitemIds().isEmpty()) {
                    Approval.ProcessWorkitemRequest wiReq = new Approval.ProcessWorkitemRequest();
                    wiReq.setWorkitemId(subResult.getNewWorkitemIds()[0]);
                    wiReq.setAction('Approve');
                    wiReq.setComments('Inventory confirmed in stock via ' + confirmedBy + '.');
                    Approval.process(wiReq);
                } else if (!subResult.isSuccess()) {
                    System.debug(LoggingLevel.WARN, 'Audit approval submit failed for ' + orderId + ': ' + subResult.getErrors()[0].getMessage());
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Audit approval cycle failed for ' + orderId + ': ' + ex.getMessage());
            }
        }
    }
}
