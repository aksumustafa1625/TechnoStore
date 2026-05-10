// Create 8 JIRA tickets for the SAP integration sprint and add them all to Sprint 68.
// Reuses Jira_Config__c credentials and the same REST callout pattern as JiraTicketService.

Jira_Config__c cfg = Jira_Config__c.getOrgDefaults();
String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(cfg.Email__c + ':' + cfg.API_Token__c));
Integer sprintId = 68;

// 8 stories, each defined as Map<String,String> with summary, description, label list, points
List<Map<String, Object>> tickets = new List<Map<String, Object>>{
    new Map<String, Object>{
        'summary' => '[1pt] Set up SAP API Hub sandbox + credentials',
        'description' => 'Register for SAP API Hub (api.sap.com), generate sandbox API key, document endpoint URLs:\n' +
            '- Business Partner API\n' +
            '- Product Master / Material API\n' +
            '- Sales Order API\n\n' +
            'Validate access with curl. Acceptance: API key in hand, 1 successful test call documented.',
        'labels' => new List<String>{ 'sap-integration', 'setup', '1pt' }
    },
    new Map<String, Object>{
        'summary' => '[2pt] Create Mule project skeleton for SAP integration',
        'description' => 'Anypoint Code Builder project (or reuse salesforce-jira-integration as template):\n' +
            '- pom.xml with HTTP connector\n' +
            '- mule-artifact.json\n' +
            '- src/main/mule/sap-integration.xml (empty flow scaffold)\n' +
            '- dev.yaml template for SAP credentials\n\n' +
            'Acceptance: Maven build succeeds, project loads in Code Builder without errors.',
        'labels' => new List<String>{ 'sap-integration', 'mulesoft', '2pt' }
    },
    new Map<String, Object>{
        'summary' => '[1pt] Build Custom Setting Sap_Config__c',
        'description' => 'Mirror the Jira_Config__c pattern:\n' +
            '- Custom Setting (Hierarchy, Protected)\n' +
            '- Fields: Host__c, ApiKey__c, ClientId__c, ClientSecret__c\n' +
            '- Remote Site Setting for sandbox.api.sap.com\n' +
            '- Permission Set granting FLS on all fields\n\n' +
            'Acceptance: Apex can read SAP creds via Sap_Config__c.getOrgDefaults().',
        'labels' => new List<String>{ 'sap-integration', 'salesforce', '1pt' }
    },
    new Map<String, Object>{
        'summary' => '[5pt] Implement Product Master sync (SAP -> Salesforce)',
        'description' => 'Scheduled Mule flow that pulls product master from SAP:\n' +
            '- Trigger: scheduled (hourly or daily)\n' +
            '- HTTP request to SAP Material API\n' +
            '- DataWeave transform SAP material -> Salesforce Product2 schema\n' +
            '- Salesforce Connector: upsert Product2 by ExternalId (SAP_Material_Number__c)\n' +
            '- Handle pagination (SAP returns 100 records per page)\n' +
            '- Log results to CloudHub logs\n\n' +
            'Acceptance: 5 sample SAP products land in Salesforce as Product2 records with SAP_Material_Number__c populated.',
        'labels' => new List<String>{ 'sap-integration', 'mulesoft', 'inbound', '5pt' }
    },
    new Map<String, Object>{
        'summary' => '[3pt] Order Acknowledgment (Salesforce -> SAP on Activation)',
        'description' => 'When a Salesforce Order is Activated, push to SAP:\n' +
            '- Salesforce Platform Event: Order_Activated__e\n' +
            '- Mule listens, builds SAP Sales Order JSON\n' +
            '- HTTP POST to SAP Sales Order API\n' +
            '- On success: write SAP order number back to Order.SAP_Order_Number__c\n' +
            '- On failure: publish to error notification topic\n\n' +
            'Acceptance: Activating a Salesforce demo order creates a SAP sales order; SAP order number visible on Salesforce Order.',
        'labels' => new List<String>{ 'sap-integration', 'mulesoft', 'outbound', '3pt' }
    },
    new Map<String, Object>{
        'summary' => '[2pt] Error handling + retry pattern in Mule',
        'description' => 'Production-grade resilience:\n' +
            '- Mule on-error-continue + on-error-propagate\n' +
            '- Retry with exponential backoff (3 attempts, 2s/4s/8s)\n' +
            '- Dead-letter queue for permanently-failed payloads (Anypoint MQ or CloudHub Object Store)\n' +
            '- Notification to Salesforce admin via Platform Event on DLQ entries\n\n' +
            'Acceptance: simulated SAP outage triggers retries, then DLQ, then admin notification.',
        'labels' => new List<String>{ 'sap-integration', 'reliability', '2pt' }
    },
    new Map<String, Object>{
        'summary' => '[2pt] End-to-end test + sample data validation',
        'description' => 'Full round-trip verification:\n' +
            '- Pull 5 products from SAP sandbox via the inbound flow\n' +
            '- Verify Product2 records in Salesforce match SAP master data\n' +
            '- Activate 1 Salesforce demo order\n' +
            '- Verify SAP sales order exists with matching line items + amount\n' +
            '- Document any data mapping gaps\n\n' +
            'Acceptance: round-trip passes, no data loss, mapping documented.',
        'labels' => new List<String>{ 'sap-integration', 'testing', '2pt' }
    },
    new Map<String, Object>{
        'summary' => '[1pt] Demo recording prep (narrative + walkthrough)',
        'description' => 'Record-ready demo:\n' +
            '- Demo narrative script (English, DACH-appropriate)\n' +
            '- Walkthrough order: Setup -> Catalog -> Quote -> Order activate -> SAP sync\n' +
            '- Side-by-side Salesforce + SAP screens\n' +
            '- Highlight: real product master from SAP, real order to SAP\n\n' +
            'Acceptance: 5-minute clean recording, no fumbling, narrative tested.',
        'labels' => new List<String>{ 'sap-integration', 'demo', '1pt' }
    }
};

List<String> createdKeys = new List<String>();

for (Map<String, Object> t : tickets) {
    Map<String, Object> issuePayload = new Map<String, Object>{
        'fields' => new Map<String, Object>{
            'project'     => new Map<String, String>{ 'key' => cfg.Project_Key__c },
            'issuetype'   => new Map<String, String>{ 'name' => 'Task' },
            'summary'     => (String) t.get('summary'),
            'description' => (String) t.get('description'),
            'labels'      => (List<String>) t.get('labels')
        }
    };

    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://' + cfg.Host__c + '/rest/api/2/issue');
    req.setMethod('POST');
    req.setHeader('Authorization', authHeader);
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    req.setBody(JSON.serialize(issuePayload));
    req.setTimeout(60000);

    HttpResponse resp = new Http().send(req);
    if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        String key = (String) body.get('key');
        createdKeys.add(key);
        System.debug('Created ' + key + ': ' + t.get('summary'));
    } else {
        System.debug('FAIL: ' + resp.getStatusCode() + ' ' + resp.getBody());
    }
}

System.debug('---');
System.debug('Created ' + createdKeys.size() + ' tickets. Now adding to Sprint ' + sprintId);

// Bulk add all created tickets to sprint
if (!createdKeys.isEmpty()) {
    Map<String, Object> moveBody = new Map<String, Object>{ 'issues' => createdKeys };
    HttpRequest moveReq = new HttpRequest();
    moveReq.setEndpoint('https://' + cfg.Host__c + '/rest/agile/1.0/sprint/' + sprintId + '/issue');
    moveReq.setMethod('POST');
    moveReq.setHeader('Authorization', authHeader);
    moveReq.setHeader('Content-Type', 'application/json');
    moveReq.setBody(JSON.serialize(moveBody));
    moveReq.setTimeout(60000);

    HttpResponse moveResp = new Http().send(moveReq);
    System.debug('Add to sprint: HTTP ' + moveResp.getStatusCode());
    if (moveResp.getStatusCode() >= 200 && moveResp.getStatusCode() < 300) {
        System.debug('All ' + createdKeys.size() + ' tickets added to Sprint ' + sprintId);
    } else {
        System.debug('Move failed: ' + moveResp.getBody());
    }
}

System.debug('---');
System.debug('View board: https://' + cfg.Host__c + '/jira/software/projects/' + cfg.Project_Key__c + '/boards/34');
