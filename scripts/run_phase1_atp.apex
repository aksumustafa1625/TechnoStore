// Phase 1 — ATP Check. PURE CALLOUT, no setup DML in this transaction.
// Run setup_phase1_material.apex FIRST if SAP_Material_Number__c isn't set.

List<AggregateResult> hot = [
    SELECT Product2Id, COUNT(Id) cnt FROM OrderItem
    WHERE Product2Id != null GROUP BY Product2Id ORDER BY COUNT(Id) DESC LIMIT 1
];
Id pId = (Id) hot[0].get('Product2Id');
Product2 p = [SELECT Id, Name, SAP_Material_Number__c FROM Product2 WHERE Id = :pId];
System.debug('Product: ' + p.Name + ' (SAP_Material_Number__c=' + p.SAP_Material_Number__c + ')');

if (p.SAP_Material_Number__c == null) {
    System.debug('ERROR: SAP_Material_Number__c not set. Run setup_phase1_material.apex first.');
    return;
}

Order o = [SELECT Id, OrderNumber FROM Order WHERE Id IN (SELECT OrderId FROM OrderItem WHERE Product2Id = :pId) LIMIT 1];
System.debug('Order: ' + o.OrderNumber);

SapMaterialStockService.Request req = new SapMaterialStockService.Request();
req.orderId = o.Id;
List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(new List<SapMaterialStockService.Request>{ req });

for (SapMaterialStockService.Result r : results) {
    System.debug('=== PHASE 1 RESULT ===');
    System.debug('  orderId           = ' + r.orderId);
    System.debug('  sapMaterialNumber = ' + r.sapMaterialNumber);
    System.debug('  availableQuantity = ' + r.availableQuantity);
    System.debug('  status            = ' + r.status);
    System.debug('  message           = ' + r.message);
}

Order check = [SELECT Id, OrderNumber, SAP_Available_Quantity__c, SAP_Inventory_Checked_At__c FROM Order WHERE Id = :o.Id];
System.debug('=== ORDER AUDIT FIELDS ===');
System.debug('  SAP_Available_Quantity__c  = ' + check.SAP_Available_Quantity__c);
System.debug('  SAP_Inventory_Checked_At__c = ' + check.SAP_Inventory_Checked_At__c);

if (check.SAP_Available_Quantity__c != null && check.SAP_Inventory_Checked_At__c != null) {
    System.debug('>>> PHASE 1 SUCCESS: SAP returned ATP qty=' + check.SAP_Available_Quantity__c);
}
