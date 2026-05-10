// Check actual fields on Order via Schema.getGlobalDescribe
Map<String, Schema.SObjectField> fmap = Schema.SObjectType.Order.fields.getMap();
for (String f : fmap.keySet()) {
    if (f.toLowerCase().contains('jira') || f.toLowerCase().contains('inventory')) {
        System.debug('FOUND: ' + f);
    }
}
System.debug('Total Order fields: ' + fmap.size());
