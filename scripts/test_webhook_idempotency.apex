// Test webhook idempotency: fire the JIRA webhook twice with the same External_Id,
// expect 2nd call to be deduped.
Http http = new Http();
String url = 'https://your-org.develop.my.salesforce-sites.com/docusign/services/apexrest/jira/webhook?secret=technostore-warehouse-secret-2026';
String testIssueKey = 'TS-DEDUP-TEST-' + DateTime.now().getTime();
String body = JSON.serialize(new Map<String, Object>{
    'issueKey' => testIssueKey,
    'status' => 'Done'
});

System.debug('===== TEST: External_Id = ' + testIssueKey + '|Done =====');

// CALL 1 — first delivery, should process (will 404 since no Order has this JIRA_Ticket_Id)
HttpRequest req1 = new HttpRequest();
req1.setEndpoint(url);
req1.setMethod('POST');
req1.setHeader('Content-Type', 'application/json');
req1.setBody(body);
HttpResponse resp1 = http.send(req1);
System.debug('CALL 1 status=' + resp1.getStatusCode() + ' body=' + resp1.getBody());

// CALL 2 — same payload, should be deduped (200 + "duplicate delivery dropped")
HttpRequest req2 = new HttpRequest();
req2.setEndpoint(url);
req2.setMethod('POST');
req2.setHeader('Content-Type', 'application/json');
req2.setBody(body);
HttpResponse resp2 = http.send(req2);
System.debug('CALL 2 status=' + resp2.getStatusCode() + ' body=' + resp2.getBody());

// Verify Webhook_Event__c row count = 1 (dedup worked)
String externalId = testIssueKey + '|Done';
Integer rowCount = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = :externalId];
System.debug('Webhook_Event__c rows for External_Id=' + externalId + ': ' + rowCount);

if (rowCount == 1) {
    System.debug('✅ IDEMPOTENCY VERIFIED — 2 webhook calls, 1 row created');
} else {
    System.debug('❌ FAIL — expected 1 row, got ' + rowCount);
}
