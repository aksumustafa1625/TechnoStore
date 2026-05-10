// What's filling up "Batch Jobs" storage? Likely BackgroundOperation, AsyncApexJob,
// or FlowInterview / FlowExecutionErrorEvent records.

System.debug('======== BackgroundOperation count ========');
Integer bgCount = [SELECT COUNT() FROM BackgroundOperation];
System.debug('  Total: ' + bgCount);

System.debug('======== BackgroundOperation by Status ========');
for (AggregateResult ar : [SELECT Status status, COUNT(Id) cnt FROM BackgroundOperation GROUP BY Status]) {
    System.debug('  ' + ar.get('status') + ': ' + ar.get('cnt'));
}

System.debug('======== Sample BackgroundOperation (oldest 5) ========');
for (BackgroundOperation bo : [SELECT Id, Type, Status, Name, CreatedDate FROM BackgroundOperation ORDER BY CreatedDate ASC LIMIT 5]) {
    System.debug('  ' + bo.CreatedDate + ' | ' + bo.Type + ' | ' + bo.Status + ' | ' + bo.Name);
}

System.debug('======== AsyncApexJob count by Status ========');
for (AggregateResult ar : [SELECT Status status, COUNT(Id) cnt FROM AsyncApexJob GROUP BY Status]) {
    System.debug('  ' + ar.get('status') + ': ' + ar.get('cnt'));
}

System.debug('======== AsyncApexJob by JobType ========');
for (AggregateResult ar : [SELECT JobType jt, COUNT(Id) cnt FROM AsyncApexJob GROUP BY JobType]) {
    System.debug('  ' + ar.get('jt') + ': ' + ar.get('cnt'));
}
