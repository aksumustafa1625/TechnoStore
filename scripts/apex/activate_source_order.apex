Order o = [SELECT Id, OrderNumber, Status FROM Order WHERE Id='801aj00002an6D2AAI'];
System.debug('Before: ' + o.OrderNumber + ' status=' + o.Status);
o.Status = 'Activated';
try {
    update o;
    System.debug('Order updated successfully');
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
Order o2 = [SELECT Id, Status FROM Order WHERE Id='801aj00002an6D2AAI'];
System.debug('After: status=' + o2.Status);
List<Asset> newAssets = [SELECT Id, Name, Product2.Name, Quantity, Price FROM Asset WHERE AccountId='001aj00002agpI6AAI'];
System.debug('Assets on Aksu LTD: ' + newAssets.size());
for (Asset a : newAssets) {
    System.debug('  - ' + a.Name + ' (Product: ' + a.Product2.Name + ', Qty: ' + a.Quantity + ')');
}
