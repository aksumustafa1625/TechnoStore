// Create a 2-week JIRA sprint starting today on board 34 (TS project).
// Reuses Jira_Config__c credentials. Optionally moves TS-1 (or all open TS issues) into it.

Jira_Config__c cfg = Jira_Config__c.getOrgDefaults();
if (cfg == null || String.isBlank(cfg.API_Token__c)) {
    System.debug('Jira_Config__c missing — run setup_jira_config.apex first');
    return;
}

Date today = Date.today();
Date endDate = today.addDays(14);

String startIso = DateTime.newInstance(today.year(), today.month(), today.day(), 8, 0, 0).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
String endIso   = DateTime.newInstance(endDate.year(), endDate.month(), endDate.day(), 17, 0, 0).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');

// JIRA caps sprint names at 30 chars
List<String> monthNames = new List<String>{'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
String sprintName = 'TS Sprint ' + monthNames[today.month()-1] + ' ' + today.day() + '-' + endDate.day();

Map<String, Object> payload = new Map<String, Object>{
    'name' => sprintName,
    'startDate' => startIso,
    'endDate' => endIso,
    'originBoardId' => 34,
    'goal' => 'Q2 demo readiness: complete catalog qualification + inventory approval + JIRA integration.'
};

String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(cfg.Email__c + ':' + cfg.API_Token__c));
HttpRequest req = new HttpRequest();
req.setEndpoint('https://' + cfg.Host__c + '/rest/agile/1.0/sprint');
req.setMethod('POST');
req.setHeader('Authorization', authHeader);
req.setHeader('Content-Type', 'application/json');
req.setHeader('Accept', 'application/json');
req.setBody(JSON.serialize(payload));
req.setTimeout(60000);

HttpResponse resp = new Http().send(req);
System.debug('HTTP ' + resp.getStatusCode());

if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    Integer sprintId = (Integer) body.get('id');
    System.debug('Sprint created: id=' + sprintId + ' name="' + sprintName + '"');
    System.debug('Start: ' + startIso + ' End: ' + endIso);

    // Move TS-1 (any existing test ticket) into the new sprint
    Order o = [SELECT JIRA_Ticket_Id__c FROM Order WHERE JIRA_Ticket_Id__c != null LIMIT 1];
    if (o != null && String.isNotBlank(o.JIRA_Ticket_Id__c)) {
        String ticketKey = o.JIRA_Ticket_Id__c;
        Map<String, Object> moveBody = new Map<String, Object>{ 'issues' => new List<String>{ ticketKey } };

        HttpRequest moveReq = new HttpRequest();
        moveReq.setEndpoint('https://' + cfg.Host__c + '/rest/agile/1.0/sprint/' + sprintId + '/issue');
        moveReq.setMethod('POST');
        moveReq.setHeader('Authorization', authHeader);
        moveReq.setHeader('Content-Type', 'application/json');
        moveReq.setBody(JSON.serialize(moveBody));
        moveReq.setTimeout(60000);

        HttpResponse moveResp = new Http().send(moveReq);
        System.debug('Move ' + ticketKey + ' to sprint: HTTP ' + moveResp.getStatusCode());
        if (moveResp.getStatusCode() >= 200 && moveResp.getStatusCode() < 300) {
            System.debug('  ' + ticketKey + ' added to sprint ' + sprintId);
        } else {
            System.debug('  Move failed: ' + moveResp.getBody());
        }
    }

    System.debug('---');
    System.debug('View at: https://' + cfg.Host__c + '/jira/software/projects/' + cfg.Project_Key__c + '/boards/34');
} else {
    System.debug('Sprint create failed: ' + resp.getBody());
}
