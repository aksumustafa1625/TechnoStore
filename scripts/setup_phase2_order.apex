// Survey Orders, pick a candidate, try to activate
List<Order> all = [SELECT Id, OrderNumber, Status, EffectiveDate, AccountId, Pricebook2Id FROM Order ORDER BY CreatedDate DESC LIMIT 10];
System.debug('Total Orders in org: ' + [SELECT COUNT() FROM Order]);
for (Order o : all) {
    System.debug('  ' + o.OrderNumber + ' | Status=' + o.Status + ' | Account=' + o.AccountId);
}

// Try to find a Draft order to activate
List<Order> drafts = [SELECT Id, OrderNumber FROM Order WHERE Status = 'Draft' LIMIT 1];
if (!drafts.isEmpty()) {
    System.debug('Found Draft Order: ' + drafts[0].OrderNumber + ' — attempting activation');
    try {
        drafts[0].Status = 'Activated';
        update drafts[0];
        System.debug('>>> Activated: ' + drafts[0].OrderNumber);
    } catch (Exception e) {
        System.debug('Activation failed: ' + e.getMessage());
    }
}
