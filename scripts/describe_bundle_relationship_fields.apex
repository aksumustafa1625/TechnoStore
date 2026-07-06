Map<String, Schema.SObjectType> globalTypes = Schema.getGlobalDescribe();
List<Schema.SObjectType> typesToDescribe = new List<Schema.SObjectType>{
    globalTypes.get('QuoteLineRelationship'),
    globalTypes.get('Quote_Bundle_Component__c')
};

for (Schema.SObjectType sType : typesToDescribe) {
    if (sType == null) continue;
    Schema.DescribeSObjectResult obj = sType.getDescribe();
    System.debug('OBJECT ' + obj.getName() + ' createable=' + obj.isCreateable() + ' updateable=' + obj.isUpdateable() + ' deletable=' + obj.isDeletable() + ' queryable=' + obj.isQueryable());
    List<String> names = new List<String>(obj.fields.getMap().keySet());
    names.sort();
    for (String fieldName : names) {
        Schema.DescribeFieldResult d = obj.fields.getMap().get(fieldName).getDescribe();
        System.debug(
            'FIELD ' + obj.getName() + '.' + fieldName +
            ' label=' + d.getLabel() +
            ' createable=' + d.isCreateable() +
            ' updateable=' + d.isUpdateable() +
            ' type=' + d.getType()
        );
        if (d.getType() == Schema.DisplayType.Picklist) {
            List<String> activeValues = new List<String>();
            for (Schema.PicklistEntry entry : d.getPicklistValues()) {
                if (entry.isActive()) activeValues.add(entry.getValue());
            }
            System.debug('PICKLIST ' + obj.getName() + '.' + fieldName + '=' + String.join(activeValues, ','));
        }
    }
}
