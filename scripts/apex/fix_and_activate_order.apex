Order o = [SELECT Id, ShippingStreet, ShippingCity, ShippingCountry, ShippingState, ShippingPostalCode,
                  BillingStreet, BillingCity, BillingCountry, BillingState, BillingPostalCode, Status
           FROM Order WHERE Id='801aj00002an6D2AAI'];
o.ShippingStreet = o.BillingStreet;
o.ShippingCity = o.BillingCity;
o.ShippingCountry = o.BillingCountry;
o.ShippingState = o.BillingState;
o.ShippingPostalCode = o.BillingPostalCode;
o.Status = 'Activated';
try {
    update o;
    System.debug('Order activated successfully');
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}

Order after = [SELECT Id, Status FROM Order WHERE Id='801aj00002an6D2AAI'];
System.debug('Final status: ' + after.Status);

List<Asset> assets = [SELECT Id, Name, Product2.Name, Quantity, Price, Status FROM Asset WHERE AccountId='001aj00002agpI6AAI'];
System.debug('Assets on Aksu LTD: ' + assets.size());
for (Asset a : assets) {
    System.debug('  - ' + a.Name + ' | Product: ' + a.Product2.Name + ' | Qty: ' + a.Quantity + ' | Price: ' + a.Price + ' | Status: ' + a.Status);
}
