trigger OrderActivatedTrigger on Order_Activated__e (after insert) {
    Set<Id> orderIds = new Set<Id>();
    for (Order_Activated__e e : Trigger.new) {
        if (String.isNotBlank(e.Order_Id__c)) {
            try { orderIds.add((Id) e.Order_Id__c); }
            catch (Exception ex) { System.debug(LoggingLevel.WARN, 'Invalid Order_Id__c on Order_Activated__e: ' + e.Order_Id__c); }
        }
    }
    if (!orderIds.isEmpty()) SapSalesOrderService.pushOrders(orderIds);
}
