// Deep diagnostic: is the qualification engine actually running?

System.debug('======== Existing Laptop Pro Bundle qualification (proven product) ========');
// This product is supposedly disqualified for Retail. If this filters correctly on Köln, engine works.
Id laptopProId = '01taj00000QmKgdAAF';
for (ProductQualification pq : [SELECT MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate FROM ProductQualification WHERE ProductId = :laptopProId]) {
    System.debug('  PQ: Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c + ' From=' + pq.EffectiveFromDate + ' To=' + pq.EffectiveToDate);
}
for (ProductDisqualification pdq : [SELECT Industry__c, EffectiveFromDate, EffectiveToDate FROM ProductDisqualification WHERE ProductId = :laptopProId]) {
    System.debug('  PDQ: ' + pdq.Industry__c + ' From=' + pdq.EffectiveFromDate + ' To=' + pdq.EffectiveToDate);
}
// EffectiveToDate of these PDQs was 2026-07-18 21:18 — let's check if still in window
System.debug('  Today=' + Date.today());

System.debug('======== ContextDefinition records ========');
for (ContextDefinition cd : [SELECT Id, MasterLabel, DeveloperName FROM ContextDefinition LIMIT 30]) {
    System.debug('  ' + cd.DeveloperName + ' | ' + cd.MasterLabel);
}

System.debug('======== ContextDefinitionSync records ========');
for (ContextDefinitionSync cds : [SELECT Id FROM ContextDefinitionSync ORDER BY CreatedDate DESC LIMIT 10]) {
    System.debug('  ' + cds);
}

System.debug('======== Procedure-related sync state ========');
for (ProcedurePlanDefinition ppd : [SELECT Id, DeveloperName, MasterLabel, ProcessType, PrimaryObject FROM ProcedurePlanDefinition LIMIT 10]) {
    System.debug('  ' + ppd.DeveloperName + ' | ' + ppd.MasterLabel + ' | ProcessType=' + ppd.ProcessType + ' | PrimaryObject=' + ppd.PrimaryObject);
}

System.debug('======== ProcedurePlanOption (the thing memory said was blocking products) ========');
for (ProcedurePlanOption ppo : [SELECT Id FROM ProcedurePlanOption LIMIT 20]) {
    System.debug('  ' + ppo.Id);
}

System.debug('======== Check if there are Product-level visibility rules (other than PQ/PDQ) ========');
// Try ProductSellingModelOption — does it have a context for visibility?
List<ProductSellingModelOption> psmos = [SELECT Id, Product2Id, Product2.Name FROM ProductSellingModelOption WHERE Product2.ProductCode IN ('COMP-WS-PREMIUM','COMP-WS-002','COMP-WS-001')];
for (ProductSellingModelOption psmo : psmos) {
    System.debug('  ' + psmo.Product2.Name + ': PSMO Id=' + psmo.Id);
}
