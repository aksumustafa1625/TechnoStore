// Describe QuoteItemTaxItem
Schema.DescribeSObjectResult d = Schema.SObjectType.QuoteItemTaxItem;
Map<String, Schema.SObjectField> fields = d.fields.getMap();
for (String fn : fields.keySet()) {
    Schema.DescribeFieldResult f = fields.get(fn).getDescribe();
    if ((f.isCreateable() || f.isUpdateable()) && !f.isDeprecatedAndHidden()) {
        System.debug(f.getName() + ' | ' + f.getType() + ' | createable=' + f.isCreateable() + ' updateable=' + f.isUpdateable() + ' nillable=' + f.isNillable() + ' refersTo=' + f.getReferenceTo());
    }
}
