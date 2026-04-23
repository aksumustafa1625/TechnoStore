// Backfill Description on all QLI and OrderItems with null Description
// Name attribute on Quote/Order hydration mappings is pointed at Description,
// so Description must be non-null for createClmContract to succeed.

List<QuoteLineItem> qlis = [SELECT Id, Description, Product2.Name, LineNumber FROM QuoteLineItem WHERE Description = null];
for (QuoteLineItem q : qlis) {
    q.Description = (q.Product2 != null && q.Product2.Name != null) ? q.Product2.Name : ('Line ' + q.LineNumber);
}
if (!qlis.isEmpty()) update qlis;
System.debug('Updated QLIs: ' + qlis.size());

List<OrderItem> ois = [SELECT Id, Description, Product2.Name FROM OrderItem WHERE Description = null];
for (OrderItem oi : ois) {
    oi.Description = (oi.Product2 != null && oi.Product2.Name != null) ? oi.Product2.Name : 'Line Item';
}
if (!ois.isEmpty()) update ois;
System.debug('Updated OrderItems: ' + ois.size());

// Show Order 00000140 items after backfill
for (OrderItem oi : [SELECT Id, Description, Product2.Name FROM OrderItem WHERE Order.OrderNumber='00000140']) {
    System.debug('Order 140 item: ' + oi.Product2.Name + ' Desc=' + oi.Description);
}
