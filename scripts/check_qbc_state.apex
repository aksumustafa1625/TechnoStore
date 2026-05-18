// Verify Quote_Bundle_Component__c state — partial destructive deploy may have left fields in inconsistent state
try {
    Schema.DescribeSObjectResult d = Schema.describeSObjects(new String[]{ 'Quote_Bundle_Component__c' })[0];
    System.debug('Object still exists. Fields:');
    for (String fname : d.fields.getMap().keySet()) {
        System.debug('  ' + fname);
    }
} catch (Exception e) {
    System.debug('Object describe failed: ' + e.getMessage());
}
