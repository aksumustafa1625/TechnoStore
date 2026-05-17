/**
 * Controller for the WarehouseInventoryApproval Visualforce page — a dedicated approval
 * surface for the warehouse role. Slack #warehouse messages link directly here, so the
 * warehouse user never lands on the Order detail page (and the sales rep never sees the
 * Mark In Stock / Mark Out of Stock buttons on their side).
 *
 * Behavior:
 *   1. Page loads with ?orderId=<Id> query param.
 *   2. Loads the Order + line items + the active ProcessInstanceWorkitem.
 *   3. If a workitem is pending → renders the two decision buttons.
 *   4. Mark In Stock → calls Approval.process(Approve) → triggers the workflow field
 *      updates wired to the approval process: Inventory_Status__c='In Stock' AND
 *      Order.Status='Activated'.
 *   5. Mark Out of Stock → calls Approval.process(Reject) → workflow flips
 *      Inventory_Status__c='Out of Stock'; Order stays in Draft.
 *   6. After either action, the page reloads its data and shows the final state.
 */
public with sharing class WarehouseInventoryApprovalController {

    public Order targetOrder { get; private set; }
    public List<OrderItem> orderItems { get; private set; }
    public Id workitemId { get; private set; }
    public String approvalState { get; private set; } // 'Pending' | 'Approved' | 'Rejected' | 'NotFound'
    public String banner { get; set; }
    public String bannerLevel { get; set; } // 'success' | 'warning' | 'error' | 'info'

    public WarehouseInventoryApprovalController() {
        String orderIdParam = ApexPages.currentPage().getParameters().get('orderId');
        if (String.isBlank(orderIdParam)) {
            approvalState = 'NotFound';
            banner = 'Missing orderId parameter in URL.';
            bannerLevel = 'error';
            return;
        }
        try {
            Id orderId = (Id) orderIdParam;
            loadData(orderId);
        } catch (Exception e) {
            approvalState = 'NotFound';
            banner = 'Invalid order id.';
            bannerLevel = 'error';
        }
    }

    private void loadData(Id orderId) {
        List<Order> orders = [
            SELECT Id, OrderNumber, Status, TotalAmount, Account.Name,
                   Inventory_Status__c, Inventory_Confirmed_By__c, Inventory_Confirmed_At__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            approvalState = 'NotFound';
            banner = 'Order not found.';
            bannerLevel = 'error';
            return;
        }
        targetOrder = orders[0];

        orderItems = [
            SELECT Id, Product2.Name, Quantity, UnitPrice, TotalPrice
            FROM OrderItem
            WHERE OrderId = :orderId
            ORDER BY ListPrice DESC
        ];

        // Active pending workitem
        List<ProcessInstanceWorkitem> wis = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :orderId
              AND ProcessInstance.Status = 'Pending'
            LIMIT 1
        ];
        if (!wis.isEmpty()) {
            workitemId = wis[0].Id;
            approvalState = 'Pending';
            return;
        }

        // No pending workitem — look up most recent completed instance
        List<ProcessInstance> completed = [
            SELECT Status
            FROM ProcessInstance
            WHERE TargetObjectId = :orderId
            ORDER BY CompletedDate DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];
        if (!completed.isEmpty()) {
            String s = completed[0].Status;
            approvalState = (s == 'Approved') ? 'Approved' : (s == 'Rejected' ? 'Rejected' : 'NotFound');
        } else {
            approvalState = 'NotFound';
        }
    }

    public PageReference markInStock() {
        return processDecision('Approve', 'Inventory confirmed in stock', 'success');
    }

    public PageReference markOutOfStock() {
        return processDecision('Reject', 'Inventory marked out of stock', 'warning');
    }

    private PageReference processDecision(String action, String userFacingMessage, String level) {
        if (workitemId == null || approvalState != 'Pending') {
            banner = 'No pending inventory approval on this Order.';
            bannerLevel = 'error';
            return null;
        }
        try {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workitemId);
            req.setAction(action);
            req.setComments(userFacingMessage + ' via the Warehouse Inventory Review page.');
            Approval.ProcessResult result = Approval.process(req);
            if (result.isSuccess()) {
                banner = userFacingMessage + '.';
                bannerLevel = level;
                if (action == 'Reject') {
                    JiraTicketService.createTicketAsync(targetOrder.Id, 'Out of stock confirmed by warehouse via approval page.');
                }
            } else {
                String msgs = '';
                for (Database.Error err : result.getErrors()) {
                    if (msgs.length() > 0) msgs += '; ';
                    msgs += err.getMessage();
                }
                banner = 'Approval action failed: ' + msgs;
                bannerLevel = 'error';
            }
        } catch (Exception e) {
            banner = 'Error: ' + e.getMessage();
            bannerLevel = 'error';
        }
        // Reload data to reflect new state
        loadData(targetOrder.Id);
        return null;
    }

    public Boolean getCanDecide() {
        return approvalState == 'Pending' && workitemId != null;
    }
}
