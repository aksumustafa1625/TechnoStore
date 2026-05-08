// Discovery: what qualification-related sObjects + fields exist in this org?

System.debug('======== CalculationProcedure fields ========');
for (String f : new List<String>(Schema.SObjectType.CalculationProcedure.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = Schema.SObjectType.CalculationProcedure.fields.getMap().get(f).getDescribe();
    System.debug('  ' + f + ' | ' + d.getType());
}

System.debug('======== Sample CalculationProcedure records ========');
for (CalculationProcedure cp : [SELECT Id, Name FROM CalculationProcedure LIMIT 30]) {
    System.debug('  ' + cp.Name);
}

System.debug('======== Schema introspection: search for Qualification objects ========');
Map<String, Schema.SObjectType> globalSchema = Schema.getGlobalDescribe();
for (String objName : globalSchema.keySet()) {
    String lower = objName.toLowerCase();
    if (lower.contains('qualif') || lower.contains('eligibility') || lower.contains('eligib')) {
        System.debug('  ' + objName);
    }
}

System.debug('======== Schema introspection: ContextDefinition / DecisionMatrix / etc ========');
for (String objName : globalSchema.keySet()) {
    String lower = objName.toLowerCase();
    if (lower.contains('decisionmatrix') || lower.contains('decisiontable') || lower.contains('contextdefinition') || lower.contains('procedureplan')) {
        System.debug('  ' + objName);
    }
}
