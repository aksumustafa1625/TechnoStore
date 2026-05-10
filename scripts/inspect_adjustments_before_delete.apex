// Carefully inspect AttributeBasedAdjustment + AttributeAdjustmentCondition
// to see which products they reference. Only delete those for our 14 stuck products.

System.debug('======== AttributeBasedAdjustment fields ========');
Map<String, Schema.SObjectField> fm = Schema.SObjectType.AttributeBasedAdjustment.fields.getMap();
List<String> fns = new List<String>();
for (String f : fm.keySet()) {
    Schema.DescribeFieldResult d = fm.get(f).getDescribe();
    if (d.getType() == Schema.DisplayType.REFERENCE) {
        System.debug('  ' + f + ' -> ' + d.getReferenceTo());
    }
    if (d.getType() != Schema.DisplayType.ADDRESS) fns.add(f);
}

System.debug('======== ABA records (full detail) ========');
String soql = 'SELECT ' + String.join(fns, ',') + ' FROM AttributeBasedAdjustment LIMIT 50';
for (AttributeBasedAdjustment a : (List<AttributeBasedAdjustment>) Database.query(soql)) {
    System.debug(a);
}

System.debug('======== AAC fields ========');
Map<String, Schema.SObjectField> fm2 = Schema.SObjectType.AttributeAdjustmentCondition.fields.getMap();
List<String> fns2 = new List<String>();
for (String f : fm2.keySet()) {
    Schema.DescribeFieldResult d = fm2.get(f).getDescribe();
    if (d.getType() == Schema.DisplayType.REFERENCE) {
        System.debug('  ' + f + ' -> ' + d.getReferenceTo());
    }
    if (d.getType() != Schema.DisplayType.ADDRESS) fns2.add(f);
}
