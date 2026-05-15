// End-to-end test: pick an existing Order, call JiraTicketService, verify a real
// JIRA ticket appears at your-org.atlassian.net/browse/<key>.

List<Order> orders = [SELECT Id, OrderNumber, Account.Name FROM Order ORDER BY CreatedDate DESC LIMIT 1];
if (orders.isEmpty()) { System.debug('No orders found'); return; }
Order o = orders[0];
System.debug('Testing with Order ' + o.OrderNumber + ' (' + o.Account.Name + ')');

JiraTicketService.Request req = new JiraTicketService.Request();
req.orderId = o.Id;
req.reason = 'End-to-end test from Apex anonymous (not from approval flow).';

List<JiraTicketService.Result> results = JiraTicketService.createTicket(new List<JiraTicketService.Request>{ req });
for (JiraTicketService.Result r : results) {
    System.debug('Status: ' + r.status);
    System.debug('Ticket Id: ' + r.ticketId);
    System.debug('Message: ' + r.message);
}

// Verify field updated on Order
Order verify = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :o.Id];
System.debug('Order.JIRA_Ticket_Id__c = ' + verify.JIRA_Ticket_Id__c);
