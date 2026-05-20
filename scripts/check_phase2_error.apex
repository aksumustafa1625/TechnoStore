List<Integration_Error__c> errs = [
    SELECT Id, Source_System__c, Operation__c, Severity__c, Error_Message__c,
           Error_Type__c, Payload__c, Related_Record_Id__c, Correlation_Id__c, CreatedDate
    FROM Integration_Error__c
    ORDER BY CreatedDate DESC LIMIT 3
];
System.debug('Total errors found: ' + errs.size());
for (Integration_Error__c e : errs) {
    System.debug('=== ' + e.CreatedDate + ' ===');
    System.debug('  Source/Op: ' + e.Source_System__c + ' / ' + e.Operation__c);
    System.debug('  Severity:  ' + e.Severity__c);
    System.debug('  Type:      ' + e.Error_Type__c);
    System.debug('  Msg:       ' + e.Error_Message__c);
    System.debug('  Record:    ' + e.Related_Record_Id__c);
    String payload = e.Payload__c == null ? '(empty)' : e.Payload__c.left(400);
    System.debug('  Payload:   ' + payload);
}
