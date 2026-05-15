// Inspect what address-related fields exist on Account, Opportunity, Quote
// so we know what to populate.

System.debug('===== ACCOUNT ADDRESS FIELDS =====');
Schema.DescribeSObjectResult acc = Account.SObjectType.getDescribe();
for (Schema.SObjectField f : acc.fields.getMap().values()) {
    String n = f.getDescribe().getName();
    if (n.containsIgnoreCase('billing') || n.containsIgnoreCase('shipping') || n.containsIgnoreCase('address')) {
        System.debug('  ' + n + ' [' + f.getDescribe().getType() + ']');
    }
}

System.debug('===== OPPORTUNITY ADDRESS FIELDS =====');
Schema.DescribeSObjectResult opp = Opportunity.SObjectType.getDescribe();
for (Schema.SObjectField f : opp.fields.getMap().values()) {
    String n = f.getDescribe().getName();
    if (n.containsIgnoreCase('billing') || n.containsIgnoreCase('shipping') || n.containsIgnoreCase('address')) {
        System.debug('  ' + n + ' [' + f.getDescribe().getType() + ']');
    }
}

System.debug('===== QUOTE ADDRESS FIELDS =====');
Schema.DescribeSObjectResult q = Quote.SObjectType.getDescribe();
for (Schema.SObjectField f : q.fields.getMap().values()) {
    String n = f.getDescribe().getName();
    if (n.containsIgnoreCase('billing') || n.containsIgnoreCase('shipping') || n.containsIgnoreCase('address') || n.containsIgnoreCase('quoteto')) {
        System.debug('  ' + n + ' [' + f.getDescribe().getType() + ']');
    }
}

System.debug('===== ORDER ADDRESS FIELDS (for ref) =====');
Schema.DescribeSObjectResult o = Order.SObjectType.getDescribe();
for (Schema.SObjectField f : o.fields.getMap().values()) {
    String n = f.getDescribe().getName();
    if (n.containsIgnoreCase('billto') || n.containsIgnoreCase('shipto') || n.containsIgnoreCase('billing') || n.containsIgnoreCase('shipping') || n.containsIgnoreCase('address')) {
        System.debug('  ' + n + ' [' + f.getDescribe().getType() + ']');
    }
}
