Set<Id> selectedAttributePicklistValueIds = new Set<Id>{
    '0v6aj000000G24WAAS', // RAM 16GB
    '0v6aj000000G24iAAC', // SSD Hard Drive 512GB
    '0v6aj000000G24cAAC', // i7-CPU 4.7GHz
    '0v6aj000000G24RAAS'  // 15 Inch
};

List<AttributePicklistValue> valuesToUpdate = new List<AttributePicklistValue>();
for (AttributePicklistValue valueRecord : [
    SELECT Id, Name, Status
    FROM AttributePicklistValue
    WHERE Id IN :selectedAttributePicklistValueIds
]) {
    if (valueRecord.Status != 'Active') {
        valueRecord.Status = 'Active';
        valuesToUpdate.add(valueRecord);
    }
}

if (!valuesToUpdate.isEmpty()) {
    update valuesToUpdate;
}

System.debug('Activated AttributePicklistValue count: ' + valuesToUpdate.size());
