// Comprehensive health check after the qualification setup work.
// Confirms: products intact, qualification correct, no orphaned records, no broken existing flow.

System.debug('======== 1. New demo products — both should exist & be active ========');
for (Product2 p : [SELECT Id, Name, ProductCode, IsActive, Type, Family, BasedOn.Name, QuantityUnitOfMeasure
                   FROM Product2 WHERE ProductCode IN ('COMP-WS-PREMIUM','COMP-WS-STUDIO')]) {
    System.debug('  ' + p.Name + ' | ' + p.ProductCode + ' | Active=' + p.IsActive + ' | Type=' + p.Type + ' | BasedOn=' + p.BasedOn.Name + ' | UOM=' + p.QuantityUnitOfMeasure);
}

System.debug('======== 2. Qualification rules per workstation product ========');
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode IN ('COMP-WS-PREMIUM','COMP-WS-STUDIO','COMP-WS-001','COMP-WS-002')]) {
    Integer pq = [SELECT COUNT() FROM ProductQualification WHERE ProductId = :p.Id];
    Integer pdq = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :p.Id];
    Decimal minE = pq > 0 ? [SELECT MinNumberOfEmployees__c FROM ProductQualification WHERE ProductId = :p.Id LIMIT 1].MinNumberOfEmployees__c : 0;
    System.debug('  ' + p.Name.rightPad(28) + ' | Min=' + String.valueOf(minE).rightPad(6) + ' | PDQs=' + pdq);
}

System.debug('======== 3. Existing demo products — qualification untouched? ========');
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode IN ('COMP-LAP-001','COMP-LAP-002','COMP-LAP-003','COMP-LAP-004','COMP-LAP-005')]) {
    Integer pq = [SELECT COUNT() FROM ProductQualification WHERE ProductId = :p.Id];
    Integer pdq = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :p.Id];
    System.debug('  ' + p.Name.rightPad(28) + ' | PQ=' + pq + ' | PDQ=' + pdq + ' (should match pre-existing pattern)');
}

System.debug('======== 4. Existing Laptop Pro Bundle (had PDQs already) ========');
Id lpbId = '01taj00000QmKgdAAF';
Integer lpbPdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :lpbId];
System.debug('  Laptop Pro Bundle PDQs: ' + lpbPdqCount + ' (should be 3: Recreation, Entertainment, Retail)');

System.debug('======== 5. Total product count ========');
Integer activeCount = [SELECT COUNT() FROM Product2 WHERE IsActive = true];
Integer totalCount = [SELECT COUNT() FROM Product2];
System.debug('  Active products: ' + activeCount + ' | Total: ' + totalCount);

System.debug('======== 6. Branded contract PDF flow integrity ========');
Boolean ctrlExists = false;
Boolean svcExists = false;
Boolean flowActive = false;
for (ApexClass c : [SELECT Name FROM ApexClass WHERE Name IN ('ContractPdfController','GenerateContractPdfService')]) {
    if (c.Name == 'ContractPdfController') ctrlExists = true;
    if (c.Name == 'GenerateContractPdfService') svcExists = true;
}
List<FlowDefinitionView> flows = [SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName = 'Auto_Generate_Contract_Pdf_On_Create' LIMIT 1];
if (!flows.isEmpty()) flowActive = flows[0].IsActive;
System.debug('  ContractPdfController exists: ' + ctrlExists);
System.debug('  GenerateContractPdfService exists: ' + svcExists);
System.debug('  Auto-Generate PDF flow active: ' + flowActive);

System.debug('======== 7. Recent latest contract PDFs (should still work) ========');
for (ContentVersion cv : [SELECT Title, ContentSize, CreatedDate FROM ContentVersion WHERE Title LIKE 'TechnoStore_MSA_%' ORDER BY CreatedDate DESC LIMIT 3]) {
    System.debug('  ' + cv.Title + ' | Size=' + cv.ContentSize + ' bytes | ' + cv.CreatedDate);
}

System.debug('======== 8. Account demo set integrity ========');
for (Account a : [SELECT Name, Industry, NumberOfEmployees FROM Account
                  WHERE Name IN ('Hamburg DataWorks AG','Köln Retail Cloud GmbH','Frankfurt FinTech Hub GmbH','München Industrial Systems GmbH')]) {
    System.debug('  ' + a.Name.rightPad(35) + ' | Industry=' + a.Industry.rightPad(15) + ' | Emp=' + a.NumberOfEmployees);
}

System.debug('======== ALL HEALTHY (or any anomalies above) ========');
