// Detail: ProductQualification + ProductDisqualification + existing Product Qualification procedure structure

System.debug('======== ProductQualification fields ========');
for (String f : new List<String>(Schema.SObjectType.ProductQualification.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = Schema.SObjectType.ProductQualification.fields.getMap().get(f).getDescribe();
    System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo() + ' | Required=' + (!d.isNillable() && d.isCreateable() && d.getDefaultValueFormula() == null));
}

System.debug('======== ProductDisqualification fields ========');
for (String f : new List<String>(Schema.SObjectType.ProductDisqualification.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = Schema.SObjectType.ProductDisqualification.fields.getMap().get(f).getDescribe();
    System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo());
}

System.debug('======== Existing ProductQualification records ========');
for (ProductQualification pq : [SELECT Id, Name FROM ProductQualification LIMIT 10]) {
    System.debug('  ' + pq);
}

System.debug('======== ProcedurePlanDefinition fields ========');
for (String f : new List<String>(Schema.SObjectType.ProcedurePlanDefinition.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = Schema.SObjectType.ProcedurePlanDefinition.fields.getMap().get(f).getDescribe();
    System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo());
}

System.debug('======== Existing ProcedurePlanDefinition records ========');
for (ProcedurePlanDefinition ppd : [SELECT Id FROM ProcedurePlanDefinition LIMIT 20]) {
    System.debug('  ' + ppd.Id);
}

System.debug('======== Existing CalculationProcedure named Product Qualification ========');
CalculationProcedure pqProc = [SELECT Id, Name, Description, UniqueName FROM CalculationProcedure WHERE Name = 'Product Qualification' LIMIT 1];
System.debug('  ' + pqProc);
