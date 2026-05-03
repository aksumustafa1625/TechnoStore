Id contractId = '800aj00002bkFyrAAE';
Contract c = [SELECT Id, ContractNumber, Status, StartDate, EndDate, AccountId FROM Contract WHERE Id=:contractId];
System.debug('Contract: ' + c);

if (c.AccountId != null) {
    Account a = [SELECT Id, Name, BillingStreet, BillingCity, BillingCountry FROM Account WHERE Id=:c.AccountId];
    System.debug('Account: ' + a);

    List<Contact> contacts = [SELECT Id, Name, Title, Email FROM Contact WHERE AccountId=:c.AccountId ORDER BY CreatedDate DESC LIMIT 1];
    System.debug('Contacts found: ' + contacts.size());
    if (!contacts.isEmpty()) System.debug('Contact: ' + contacts[0]);

    List<Order> ordersDirect = [SELECT Id, OrderNumber, Status FROM Order WHERE ContractId=:c.Id AND Status='Activated'];
    System.debug('Orders linked to contract: ' + ordersDirect.size());

    List<Order> ordersByAccount = [SELECT Id, OrderNumber, Status, EffectiveDate FROM Order WHERE AccountId=:c.AccountId AND Status='Activated' ORDER BY CreatedDate DESC LIMIT 3];
    System.debug('Orders on account (Activated): ' + ordersByAccount.size());
    for (Order o : ordersByAccount) System.debug('  ' + o);

    if (!ordersByAccount.isEmpty()) {
        List<OrderItem> items = [SELECT Id, Quantity, UnitPrice, TotalPrice, Product2.Name FROM OrderItem WHERE OrderId=:ordersByAccount[0].Id];
        System.debug('OrderItems on order ' + ordersByAccount[0].OrderNumber + ': ' + items.size());
        for (OrderItem oi : items) System.debug('  ' + oi.Product2.Name + ' x' + oi.Quantity + ' = ' + oi.TotalPrice);
    }
}
