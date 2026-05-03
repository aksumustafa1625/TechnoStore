// Test QuoteItemTaxItem access
try {
    Integer cnt = [SELECT COUNT() FROM QuoteItemTaxItem];
    System.debug('QuoteItemTaxItem count = ' + cnt);

    Schema.SObjectType t = Schema.getGlobalDescribe().get('QuoteItemTaxItem');
    System.debug('Type lookup: ' + t);
    if (t != null) {
        Map<String,Schema.SObjectField> fields = t.getDescribe().fields.getMap();
        System.debug('Fields count: ' + fields.size());
        for (String fn : fields.keySet()) {
            Schema.DescribeFieldResult f = fields.get(fn).getDescribe();
            if (f.isCreateable()) {
                System.debug('CREATEABLE: ' + f.getName() + ' (' + f.getType() + ')');
            }
        }
    }
} catch (Exception e) {
    System.debug('ERROR: ' + e.getTypeName() + ' ' + e.getMessage());
}
