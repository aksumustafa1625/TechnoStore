// Record counts per major sObject for storage cleanup planning
System.debug('=== KEY DEMO EVIDENCE (would prefer to keep) ===');
Integer bechtle = Database.countQuery('SELECT COUNT() FROM Account WHERE SAP_BP_Number__c = \'1018\'');
System.debug('Bechtle AG (BP 1018): ' + bechtle);
for (String num : new List<String>{'00000170','00000169','00000165'}) {
    Integer c = Database.countQuery('SELECT COUNT() FROM Order WHERE OrderNumber = \'' + num + '\'');
    System.debug('Order ' + num + ': ' + c);
}
for (String num : new List<String>{'DOC-000000016','DOC-000000017'}) {
    Integer c = Database.countQuery('SELECT COUNT() FROM Invoice WHERE DocumentNumber = \'' + num + '\'');
    System.debug('Invoice ' + num + ': ' + c);
}

System.debug('');
System.debug('=== TOTAL COUNTS (deletion scope) ===');
List<String> objs = new List<String>{
    'Account','Contact','Lead','Opportunity','OpportunityLineItem',
    'Quote','QuoteLineItem','Order','OrderItem','Asset',
    'Invoice','Contract','Task','Event','ContentVersion','ContentDocument',
    'EmailMessage','FeedItem','Note','Attachment','Product2','PricebookEntry',
    'Webhook_Event__c','Integration_Error__c','Demo_Invoice__c','Service_Activation__c',
    'Quote_Bundle_Component__c','ProcessInstance','ProcessInstanceStep'
};
for (String o : objs) {
    try {
        Integer c = Database.countQuery('SELECT COUNT() FROM ' + o);
        if (c > 0) System.debug('  ' + o + ': ' + c);
    } catch (Exception e) {
        // skip — object not queryable or doesn't exist
    }
}
