DecisionTable dt = [
    SELECT Id
    FROM DecisionTable
    WHERE DeveloperName = 'Product_Qualification'
    LIMIT 1
];

List<DecisionTableParameter> existing = [
    SELECT Id, FieldName, Sequence
    FROM DecisionTableParameter
    WHERE DecisionTableId = :dt.Id
    AND Usage = 'INPUT'
    ORDER BY Sequence
];

Boolean alreadyExists = false;
for (DecisionTableParameter param : existing) {
    if (param.FieldName == 'Industry__c') {
        alreadyExists = true;
    }
}

if (!alreadyExists) {
    insert new DecisionTableParameter(
        DecisionTableId = dt.Id,
        FieldName = 'Industry__c',
        FieldPath = 'Industry__c',
        Operator = 'Equals',
        Usage = 'INPUT',
        Sequence = 8,
        DataType = 'String',
        IsRequired = false,
        IsGroupByField = false
    );
}

for (DecisionTableParameter param : [
    SELECT Id, FieldName, FieldPath, Operator, Usage, Sequence, DataType, IsRequired
    FROM DecisionTableParameter
    WHERE DecisionTableId = :dt.Id
    ORDER BY Usage, Sequence
]) {
    System.debug(param);
}
