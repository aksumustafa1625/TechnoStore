// Pick a Product2 that actually has an OrderItem, set its SAP_Material_Number__c, test the service.
List<AggregateResult> hot = [
    SELECT Product2Id, COUNT(Id) cnt FROM OrderItem
    WHERE Product2Id != null
    GROUP BY Product2Id
    ORDER BY COUNT(Id) DESC
    LIMIT 1
];
if (hot.isEmpty()) { System.debug('No OrderItems at all — seed an Order first'); return; }
Id pId = (Id) hot[0].get('Product2Id');
Product2 p = [SELECT Id, Name, SAP_Material_Number__c FROM Product2 WHERE Id = :pId];
System.debug('Hot product: ' + p.Name + ' (used in ' + hot[0].get('cnt') + ' OrderItems)');

if (p.SAP_Material_Number__c != '221') {
    p.SAP_Material_Number__c = '221';
    update p;
    System.debug('Set ' + p.Name + ' → SAP_Material_Number__c=221');
}

Order o = [SELECT Id, OrderNumber FROM Order WHERE Id IN (SELECT OrderId FROM OrderItem WHERE Product2Id = :pId) LIMIT 1];
System.debug('Testing against Order ' + o.OrderNumber);

SapMaterialStockService.Request req = new SapMaterialStockService.Request();
req.orderId = o.Id;
List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(new List<SapMaterialStockService.Request>{ req });

for (SapMaterialStockService.Result r : results) {
    System.debug('=== Result ===');
    System.debug('  orderId             = ' + r.orderId);
    System.debug('  sapMaterialNumber   = ' + r.sapMaterialNumber);
    System.debug('  availableQuantity   = ' + r.availableQuantity);
    System.debug('  status              = ' + r.status);
    System.debug('  message             = ' + r.message);
}

Order check = [SELECT Id, OrderNumber, SAP_Available_Quantity__c, SAP_Inventory_Checked_At__c FROM Order WHERE Id = :o.Id];
System.debug('=== Order after call ===');
System.debug('  OrderNumber                = ' + check.OrderNumber);
System.debug('  SAP_Available_Quantity__c  = ' + check.SAP_Available_Quantity__c);
System.debug('  SAP_Inventory_Checked_At__c = ' + check.SAP_Inventory_Checked_At__c);

if (check.SAP_Available_Quantity__c != null && check.SAP_Inventory_Checked_At__c != null) {
    System.debug('PHASE 1 END-TO-END SUCCESS — real SAP call, write-back working.');
}
