// Survey Orders + OrderItems to pick a good source for a demo Demo_Invoice__c
for (Order o : [
    SELECT Id, OrderNumber, Status, AccountId, Account.Name, TotalAmount,
           Account.BillingStreet, Account.BillingCity, Account.BillingPostalCode, Account.BillingCountry,
           (SELECT Id, Product2.Name, Quantity, UnitPrice, TotalPrice FROM OrderItems)
    FROM Order ORDER BY CreatedDate DESC LIMIT 5
]) {
    System.debug('=== Order ' + o.OrderNumber + ' (Status=' + o.Status + ') ===');
    System.debug('  Account: ' + o.Account.Name);
    System.debug('  Billing: ' + o.Account.BillingStreet + ', ' + o.Account.BillingPostalCode
        + ' ' + o.Account.BillingCity + ', ' + o.Account.BillingCountry);
    System.debug('  TotalAmount: ' + o.TotalAmount);
    System.debug('  OrderItems (' + o.OrderItems.size() + '):');
    for (OrderItem oi : o.OrderItems) {
        System.debug('    - ' + oi.Product2.Name + ' | Qty=' + oi.Quantity
            + ' | UnitPrice=' + oi.UnitPrice + ' | Total=' + oi.TotalPrice);
    }
}
