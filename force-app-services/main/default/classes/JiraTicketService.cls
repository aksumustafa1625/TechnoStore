/**
 * Creates a JIRA Cloud issue when an Order is marked Out of Stock by the warehouse
 * Inventory Approval flow. Apex REST callout via Basic Auth (email + API token),
 * credentials sourced from Jira_Config__c protected Custom Setting.
 *
 * Mirrors the DocuSign integration pattern: outbound from Salesforce, stores the
 * external system's record id back on the Order (JIRA_Ticket_Id__c) for traceability.
 *
 * Why a direct Apex callout (not MuleSoft) for JIRA:
 *   Stripe / Sendcloud / Slack live behind a Mule layer for transformation, retry,
 *   and queueing. JIRA ticket creation is low-volume and synchronous — a Mule hop
 *   would add latency without value. This class is the right fit.
 */
public with sharing class JiraTicketService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
        @InvocableVariable(label='Reason' description='Optional context, e.g. warehouse decision comment')
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='JIRA Ticket Id')
        public String ticketId;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Create JIRA Ticket for Out-of-Stock Order' description='Posts to JIRA Cloud REST API to open a ticket for the given Order. Writes JIRA ticket key back to Order.JIRA_Ticket_Id__c.')
    public static List<Result> createTicket(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Jira_Config__c cfg = Jira_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Host__c) || String.isBlank(cfg.Email__c) || String.isBlank(cfg.API_Token__c) || String.isBlank(cfg.Project_Key__c)) {
            for (Request r : requests) {
                Result res = new Result();
                res.status = 'Error';
                res.message = 'Jira_Config__c is missing or incomplete. Set Host, Email, API_Token, and Project_Key on org default.';
                results.add(res);
            }
            return results;
        }

        Set<Id> orderIds = new Set<Id>();
        for (Request r : requests) if (r.orderId != null) orderIds.add(r.orderId);

        Map<Id, Order> orderMap = new Map<Id, Order>([
            SELECT Id, OrderNumber, Account.Name, TotalAmount, Status, Inventory_Status__c
            FROM Order WHERE Id IN :orderIds
        ]);

        Map<Id, Decimal> lineCountByOrder = new Map<Id, Decimal>();
        Map<Id, List<String>> itemNamesByOrder = new Map<Id, List<String>>();
        for (OrderItem oi : [SELECT OrderId, Quantity, Product2.Name FROM OrderItem WHERE OrderId IN :orderIds]) {
            lineCountByOrder.put(oi.OrderId, (lineCountByOrder.containsKey(oi.OrderId) ? lineCountByOrder.get(oi.OrderId) : 0) + 1);
            if (!itemNamesByOrder.containsKey(oi.OrderId)) itemNamesByOrder.put(oi.OrderId, new List<String>());
            itemNamesByOrder.get(oi.OrderId).add('- ' + oi.Product2.Name + ' x ' + (oi.Quantity == null ? '1' : String.valueOf(oi.Quantity.intValue())));
        }

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<Order> ordersToUpdate = new List<Order>();

        for (Request r : requests) {
            Result res = new Result();
            Order o = orderMap.get(r.orderId);
            if (o == null) {
                res.status = 'Error';
                res.message = 'Order not found: ' + r.orderId;
                results.add(res);
                continue;
            }

            String itemsBlock = '(no items)';
            if (itemNamesByOrder.containsKey(o.Id)) itemsBlock = String.join(itemNamesByOrder.get(o.Id), '\n');

            String description = 'Inventory out of stock — warehouse follow-up needed.\n\n'
                + 'Order: ' + o.OrderNumber + '\n'
                + 'Account: ' + (o.Account != null ? o.Account.Name : '(unknown)') + '\n'
                + 'Total: $' + (o.TotalAmount == null ? '0' : String.valueOf(o.TotalAmount.setScale(2))) + '\n'
                + 'Lines: ' + (lineCountByOrder.containsKey(o.Id) ? String.valueOf(lineCountByOrder.get(o.Id).intValue()) : '0') + '\n\n'
                + 'Products:\n' + itemsBlock + '\n\n'
                + 'Salesforce link: ' + baseUrl + '/' + o.Id + '\n\n'
                + (String.isBlank(r.reason) ? '' : 'Warehouse note: ' + r.reason + '\n\n')
                + 'Action required: confirm stock availability, replenish if needed, and update Salesforce inventory status.';

            Map<String, Object> issuePayload = new Map<String, Object>{
                'fields' => new Map<String, Object>{
                    'project'   => new Map<String, String>{ 'key' => cfg.Project_Key__c },
                    'issuetype' => new Map<String, String>{ 'name' => 'Task' },
                    'summary'   => 'Inventory check needed: ' + o.OrderNumber + ' - ' + (o.Account != null ? o.Account.Name : 'Unknown Account'),
                    'description' => description,
                    'priority'  => new Map<String, String>{ 'name' => 'High' },
                    'labels'    => new List<String>{ 'inventory', 'warehouse', 'salesforce-auto' }
                }
            };

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint('https://' + cfg.Host__c + '/rest/api/2/issue');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Accept', 'application/json');
                String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(cfg.Email__c + ':' + cfg.API_Token__c));
                req.setHeader('Authorization', authHeader);
                req.setBody(JSON.serialize(issuePayload));
                req.setTimeout(60000);

                HttpResponse resp = new Http().send(req);
                if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
                    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                    String ticketKey = (String) body.get('key');
                    res.status = 'Success';
                    res.ticketId = ticketKey;
                    res.message = 'JIRA ticket created: ' + ticketKey;

                    Order upd = new Order(Id = o.Id, JIRA_Ticket_Id__c = ticketKey);
                    ordersToUpdate.add(upd);
                } else {
                    res.status = 'Error';
                    res.message = 'JIRA HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
                }
            } catch (Exception e) {
                res.status = 'Error';
                res.message = 'Callout failed: ' + e.getTypeName() + ' - ' + e.getMessage();
            }
            results.add(res);
        }

        if (!ordersToUpdate.isEmpty()) {
            try {
                update ordersToUpdate;
            } catch (Exception e) {
                System.debug('JiraTicketService: failed to write JIRA_Ticket_Id__c back to Order(s): ' + e.getMessage());
            }
        }
        return results;
    }
}
