// Setup transaction: ensure the hot product has SAP_Material_Number__c=221
List<AggregateResult> hot = [
    SELECT Product2Id, COUNT(Id) cnt FROM OrderItem
    WHERE Product2Id != null
    GROUP BY Product2Id
    ORDER BY COUNT(Id) DESC
    LIMIT 1
];
if (hot.isEmpty()) { System.debug('No OrderItems at all'); return; }
Id pId = (Id) hot[0].get('Product2Id');
Product2 p = [SELECT Id, Name, SAP_Material_Number__c FROM Product2 WHERE Id = :pId];

if (p.SAP_Material_Number__c != '221') {
    p.SAP_Material_Number__c = '221';
    update p;
    System.debug('Updated ' + p.Name + ' → SAP_Material_Number__c=221');
} else {
    System.debug('Already set: ' + p.Name + ' SAP_Material_Number__c=' + p.SAP_Material_Number__c);
}
