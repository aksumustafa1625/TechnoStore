// Find what's eating storage under "Batch Jobs" classification

List<String> objectsToCheck = new List<String>{
    'ApexLog', 'ProcessInstance', 'ProcessInstanceStep', 'ProcessInstanceWorkitem',
    'ContextDefinitionSync', 'BulkApiJob', 'BulkApiResult',
    'FlowInterview', 'FlowExecutionErrorEvent', 'ProductFulfillmentContextSync',
    'FieldServiceMobileSettings', 'PendingServiceRoutingExtractEvent',
    'CronJobDetail', 'CronTrigger', 'CalcSummaryQueueable',
    'SetupAuditTrail', 'ContentDocumentLink'
};
for (String objName : objectsToCheck) {
    try {
        Integer cnt = Database.countQuery('SELECT COUNT() FROM ' + objName);
        if (cnt > 0) System.debug('  ' + objName + ': ' + cnt);
    } catch (Exception e) {
        // skip if not queryable
    }
}
