// Verify what's actually in Contract 00000301 right now —
// is the data complete enough that a PDF regen would produce something good?

Contract c = [
    SELECT Id, ContractNumber, Status, StartDate, EndDate, ContractTerm,
           AccountId, Account.Name, Description, OwnerId, Owner.Name,
           CustomerSignedId, CustomerSigned.Name, CustomerSigned.Email,
           CustomerSignedTitle, CustomerSignedDate,
           CompanySignedId, CompanySigned.Name, CompanySignedDate,
           BillingStreet, BillingCity, BillingPostalCode, BillingCountry
    FROM Contract WHERE ContractNumber = '00000301' LIMIT 1
];
System.debug('======== CONTRACT ========');
System.debug('ContractNumber = ' + c.ContractNumber);
System.debug('Status = ' + c.Status);
System.debug('StartDate = ' + c.StartDate);
System.debug('EndDate = ' + c.EndDate);
System.debug('ContractTerm = ' + c.ContractTerm);
System.debug('Account = ' + (c.Account != null ? c.Account.Name : '(null)'));
System.debug('Description = ' + c.Description);
System.debug('Owner = ' + (c.Owner != null ? c.Owner.Name : '(null)'));
System.debug('CustomerSigned = ' + (c.CustomerSigned != null ? c.CustomerSigned.Name + ' / ' + c.CustomerSigned.Email : '(null)'));
System.debug('CompanySigned = ' + (c.CompanySigned != null ? c.CompanySigned.Name : '(null)'));

System.debug('======== ACCOUNT ========');
if (c.AccountId != null) {
    Account a = [SELECT Id, Name, BillingStreet, BillingCity, BillingPostalCode, BillingCountry, Industry, Phone, Website
                 FROM Account WHERE Id = :c.AccountId];
    System.debug(a);
}

System.debug('======== ASSOCIATED ORDER + LINE ITEMS ========');
List<Order> orders = [
    SELECT Id, OrderNumber, Status, EffectiveDate, AccountId, ContractId,
           TotalAmount, TotalTaxAmount,
           (SELECT Id, Quantity, UnitPrice, TotalPrice, ListPrice, Product2.Name FROM OrderItems)
    FROM Order
    WHERE AccountId = :c.AccountId
    ORDER BY CreatedDate DESC LIMIT 5
];
for (Order o : orders) {
    System.debug('Order ' + o.OrderNumber + ' | Status=' + o.Status + ' | TotalAmount=' + o.TotalAmount + ' | Tax=' + o.TotalTaxAmount + ' | ContractId=' + o.ContractId);
    for (OrderItem oi : o.OrderItems) {
        System.debug('  - ' + oi.Product2.Name + ' | Qty=' + oi.Quantity + ' | Unit=' + oi.UnitPrice + ' | List=' + oi.ListPrice + ' | Total=' + oi.TotalPrice);
    }
}

System.debug('======== CONTRACT CONTACT ROLES ========');
for (ContractContactRole ccr : [SELECT Contact.Name, Contact.Email, Contact.Title, Role, IsPrimary FROM ContractContactRole WHERE ContractId = :c.Id]) {
    System.debug(ccr.Contact.Name + ' | ' + ccr.Contact.Email + ' | ' + ccr.Contact.Title + ' | Role=' + ccr.Role + ' | IsPrimary=' + ccr.IsPrimary);
}
