/**
 * Wraps the standard Salesforce Approval Process so that warehouse users can confirm or
 * reject an inventory check using friendly Order quick actions ("Mark In Stock" /
 * "Mark Out of Stock") instead of the generic Approve/Reject buttons.
 *
 * Internally the action just calls Approval.process(...) with Approve or Reject — every
 * benefit of the approval process is preserved (record lock during pending state, audit
 * history, final approval/rejection field updates).
 *
 * Guard: if the Order is not currently in a pending approval, the Apex returns a clear
 * status message instead of silently no-op'ing. The sales rep cannot bypass the warehouse
 * step by hitting these actions before submitting for approval.
 */
public with sharing class InventoryApprovalDecisionService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
        @InvocableVariable(required=true label='Decision' description='Either "Approve" (Mark In Stock) or "Reject" (Mark Out of Stock)')
        public String decision;
    }

    public class Result {
        @InvocableVariable(label='Status message')
        public String statusMessage;
    }

    @InvocableMethod(label='Inventory Approval Decision' description='Approves (In Stock) or rejects (Out of Stock) the active inventory approval workitem on the given Order.')
    public static List<Result> decide(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> orderIds = new Set<Id>();
        for (Request r : requests) if (r.orderId != null) orderIds.add(r.orderId);

        // Find the pending approval workitem for each order
        Map<Id, Id> workitemByOrder = new Map<Id, Id>();
        for (ProcessInstanceWorkitem wi : [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :orderIds
              AND ProcessInstance.Status = 'Pending'
        ]) {
            workitemByOrder.put(wi.ProcessInstance.TargetObjectId, wi.Id);
        }

        for (Request r : requests) {
            Result res = new Result();
            Id wiId = workitemByOrder.get(r.orderId);
            if (wiId == null) {
                res.statusMessage = 'No pending inventory approval found on this Order. Click "Request Inventory Check" first.';
                results.add(res);
                continue;
            }

            String action = (r.decision == 'Approve') ? 'Approve' : 'Reject';
            String comments = (action == 'Approve')
                ? 'Inventory confirmed in stock by warehouse.'
                : 'Inventory marked out of stock by warehouse.';

            try {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(wiId);
                req.setAction(action);
                req.setComments(comments);
                Approval.ProcessResult ar = Approval.process(req);
                if (ar.isSuccess()) {
                    res.statusMessage = (action == 'Approve')
                        ? 'Inventory marked In Stock. Approval recorded.'
                        : 'Inventory marked Out of Stock. Approval recorded.';
                } else {
                    String msgs = '';
                    for (Database.Error err : ar.getErrors()) {
                        if (msgs.length() > 0) msgs += '; ';
                        msgs += err.getMessage();
                    }
                    res.statusMessage = 'Approval action failed: ' + msgs;
                }
            } catch (Exception e) {
                res.statusMessage = 'Approval action error: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
