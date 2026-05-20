Schema.DescribeSObjectResult d = Integration_Error__c.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fields = d.fields.getMap();
List<String> names = new List<String>(fields.keySet());
names.sort();
System.debug('=== Integration_Error__c fields in org ===');
for (String n : names) {
    System.debug('  ' + fields.get(n).getDescribe().getName());
}
