// Bulk publish STAR entries 8-14: CLM Lifecycle + DocuSign + MuleSoft Auth + Stripe

List<NotionPublishService.StarEntry> entries = new List<NotionPublishService.StarEntry>();

// ===== 8. CLM Lifecycle Buttons + Asset Creation =====
NotionPublishService.StarEntry e8 = new NotionPublishService.StarEntry();
e8.title = '8. CLM Lifecycle Buttons + Asset Creation';
e8.situation = 'CLM native lifecycle buttons (Submit / Sign / Approve / Activate) were unreliable. Activate must invoke Asset creation API but only Autolaunched flows can call createOrUpdateAssetFromOrder â€” screen flows have no access to this invocable. Need 4 working buttons covering full Quote-to-Cash close.';
e8.taskText = 'Build 4 custom screen flows replacing native lifecycle buttons, with Activate triggering Asset creation via Autolaunched subflow indirection to bypass the screen-flow restriction.';
e8.actions = new List<String>{
    'Built 4 separate screen flows on Contract: Submit_For_Approval / Send_For_Signature / Approve_Contract / Activate_Contract',
    'Activate_Contract screen flow â†’ calls Autolaunched subflow Activate_And_Create_Asset which invokes createOrUpdateAssetFromOrder',
    'Found AssetContractRelationship blocked when SfContract field set â€” required AppUsageAssignment configuration that conflicts with RLM',
    'Worked around by sourcing Asset from Order rather than Contract directly â€” Order.QuoteId points back to Contract via parent chain',
    'Result: each button is a quick action with corresponding flow, full lifecycle visible on Contract page'
};
e8.result = 'Contract page has 4 working buttons replacing broken native CLM. Activate creates Asset linked to Account + Order. Full Q2C lifecycle complete: Quote â†’ Order â†’ Contract â†’ Approve â†’ Sign â†’ Activate â†’ Asset. Documented in clm_lifecycle_buttons_q2c.md memory.';
NotionPublishService.CodeSnippet e8c1 = new NotionPublishService.CodeSnippet();
e8c1.caption = 'Screen flow â†’ autolaunched subflow pattern';
e8c1.language = 'xml';
e8c1.code = '<!-- Screen flow calls Autolaunched subflow -->\n<subflows>\n    <name>Call_Asset_Creation</name>\n    <flowName>Activate_And_Create_Asset</flowName>\n    <inputAssignments>\n        <name>orderIdInput</name>\n        <value>\n            <elementReference>contractRecord.OrderId__c</elementReference>\n        </value>\n    </inputAssignments>\n</subflows>\n\n<!-- Autolaunched subflow invokes Asset creation -->\n<actionCalls>\n    <name>Create_Asset</name>\n    <actionName>createOrUpdateAssetFromOrder</actionName>\n    <actionType>apex</actionType>\n    <inputParameters>\n        <name>orderId</name>\n        <value>\n            <elementReference>orderIdInput</elementReference>\n        </value>\n    </inputParameters>\n</actionCalls>';
e8.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e8c1 };
entries.add(e8);

// ===== 9. Inventory Approval Workflow + Custom VF Page =====
NotionPublishService.StarEntry e9 = new NotionPublishService.StarEntry();
e9.title = '9. Inventory Approval â€” Warehouse Slack Workflow + Custom VF Page';
e9.situation = 'After Order activation, warehouse team needs to verify stock physically before fulfillment. Original design had Mark In Stock / Mark Out of Stock buttons on Order page layout â€” same user activates Order AND marks stock, violating separation of duties principle. Need workflow that routes decision to dedicated warehouse role.';
e9.taskText = 'Move stock decision to dedicated warehouse role accessed via Slack notification, enforcing separation of duties between Sales (Order activator) and Operations (stock approver).';
e9.actions = new List<String>{
    'Created Inventory_Check_Requested__e Platform Event with fields: OrderId__c, AccountName__c, TotalAmount__c, ApprovalUrl__c',
    'Built OrderTriggerHandler.afterUpdate publishing event on Status change to Activated',
    'Mule subscriber routes event payload to Slack #warehouse incoming webhook with deep-link to custom approval page',
    'Built WarehouseInventoryApproval Visualforce page with Mark In Stock / Mark Out of Stock buttons',
    'Removed inventory buttons from Order page layout entirely â€” separation of duties enforced architecturally not just by policy'
};
e9.result = 'Order activated â†’ Slack #warehouse receives notification within 3 seconds with custom VF approval link â†’ warehouse user clicks link â†’ marks stock outcome â†’ Order.Inventory_Status__c updated. Auto-activate flow skipped on BillToContactId-null demo accounts. Pattern in inventory_approval_warehouse_flow.md.';
NotionPublishService.CodeSnippet e9c1 = new NotionPublishService.CodeSnippet();
e9c1.caption = 'Platform Event publish from trigger';
e9c1.language = 'java';
e9c1.code = '// OrderTriggerHandler.afterUpdate\nList<Inventory_Check_Requested__e> events = new List<Inventory_Check_Requested__e>();\nfor (Order o : Trigger.new) {\n    Order oldO = (Order) Trigger.oldMap.get(o.Id);\n    if (o.Status == \'Activated\' && oldO.Status != \'Activated\') {\n        events.add(new Inventory_Check_Requested__e(\n            OrderId__c = o.Id,\n            AccountName__c = o.Account.Name,\n            TotalAmount__c = o.TotalAmount,\n            ApprovalUrl__c = System.URL.getOrgDomainUrl().toExternalForm()\n                + \'/apex/WarehouseInventoryApproval?id=\' + o.Id\n        ));\n    }\n}\nList<Database.SaveResult> results = EventBus.publish(events);';
e9.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e9c1 };
entries.add(e9);

// ===== 10. DocuSign Outbound â€” Apex Callout =====
NotionPublishService.StarEntry e10 = new NotionPublishService.StarEntry();
e10.title = '10. DocuSign Outbound â€” Apex Callout via Named Credential';
e10.situation = 'Salesforce CLM native Send for Signature button silently failed in our org. After 7 hypothesis iterations confirmed via Salesforce docs that LegalName auto-fill is intentionally disabled for Signer type â€” Signer Name field is meant to be blank at template-binding time. The fix is "build your own Send UI", not "fix native".';
e10.taskText = 'Build a custom Send for Signature screen flow that calls DocuSign envelope API directly and bypasses the broken native button entirely.';
e10.actions = new List<String>{
    'Built DocuSignSendService.cls â€” Apex callout to DocuSign /v2.1/accounts/{accountId}/envelopes endpoint',
    'Used Named Credential DocuSign_API for OAuth token management (auto-refresh on 401)',
    'Created envelope with base64-encoded Contract PDF (from ContentVersion VersionData), Anchor Tab signing fields',
    'Invoked from custom Send_For_Signature screen flow passing Contract.Id and recipient email',
    'Updated Contract.Status to "Awaiting Signature" + stored DocuSign envelopeId on Contract.DocuSign_Envelope_Id__c for later webhook correlation'
};
e10.result = 'Send button on Contract layout works reliably. Customer receives DocuSign signing email within seconds. Contract status flips to Awaiting Signature visible to all sales team. Documented full bidirectional integration in docusign_integration_progress.md memory.';
NotionPublishService.CodeSnippet e10c1 = new NotionPublishService.CodeSnippet();
e10c1.caption = 'DocuSignSendService envelope create';
e10c1.language = 'java';
e10c1.code = 'public static String sendEnvelope(Id contractId, String signerEmail, String signerName) {\n    ContentVersion cv = [SELECT VersionData FROM ContentVersion\n                         WHERE FirstPublishLocationId = :contractId LIMIT 1];\n\n    Map<String, Object> envelope = new Map<String, Object>{\n        \'emailSubject\' => \'TechnoStore Contract â€” Signature Required\',\n        \'documents\' => new List<Object>{\n            new Map<String, Object>{\n                \'documentBase64\' => EncodingUtil.base64Encode(cv.VersionData),\n                \'name\' => \'Contract.pdf\',\n                \'fileExtension\' => \'pdf\',\n                \'documentId\' => \'1\'\n            }\n        },\n        \'recipients\' => new Map<String, Object>{ \'signers\' => signers },\n        \'status\' => \'sent\'\n    };\n\n    HttpRequest req = new HttpRequest();\n    req.setEndpoint(\'callout:DocuSign_API/v2.1/accounts/\' + accountId + \'/envelopes\');\n    req.setMethod(\'POST\');\n    req.setBody(JSON.serialize(envelope));\n    return parseEnvelopeId(new Http().send(req).getBody());\n}';
e10.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e10c1 };
entries.add(e10);

// ===== 11. DocuSign Inbound Webhook =====
NotionPublishService.StarEntry e11 = new NotionPublishService.StarEntry();
e11.title = '11. DocuSign Inbound Webhook â€” Site + Guest User + Platform Event';
e11.situation = 'When customer signs DocuSign envelope, Salesforce needs to auto-update Contract.Status to Signed without manual intervention. DocuSign Connect requires a public webhook URL. Guest User on Salesforce Site cannot directly update Contract.Status (FLS restrictions on standard Status field).';
e11.taskText = 'Build inbound webhook receiving DocuSign event with Site + Guest User indirection via Platform Event to bypass Guest User FLS limitations on Contract.Status.';
e11.actions = new List<String>{
    'Created Salesforce Site /docusign_webhook hosting REST endpoint',
    'Built DocuSignWebhookController as @RestResource exposing POST endpoint, parses envelope status from DocuSign Connect payload',
    'Guest User publishes DocuSign_Signed__e Platform Event carrying envelopeId â€” Guest can publish events but not update Contract directly',
    'Created subscriber trigger on DocuSign_Signed__e â€” runs in system context with full FLS, updates Contract.Status to Signed by envelopeId match',
    'Configured DocuSign Connect with HTTPS Site URL + retry policy + verified signature header'
};
e11.result = 'Customer signs in DocuSign â†’ 3-5 seconds later Contract.Status auto-flips to Signed in Salesforce. Bidirectional integration complete. No manual reconciliation. Guest User + Platform Event indirection pattern reusable for any inbound webhook needing internal record updates.';
NotionPublishService.CodeSnippet e11c1 = new NotionPublishService.CodeSnippet();
e11c1.caption = 'Guest User webhook + Platform Event indirection';
e11c1.language = 'java';
e11c1.code = '@RestResource(urlMapping=\'/docusign_webhook/*\')\nglobal with sharing class DocuSignWebhookController {\n    @HttpPost\n    global static void receiveSignedEvent() {\n        String body = RestContext.request.requestBody.toString();\n        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);\n        String envelopeId = (String) ((Map<String,Object>) payload.get(\'envelopeStatus\')).get(\'envelopeId\');\n        String status = (String) ((Map<String,Object>) payload.get(\'envelopeStatus\')).get(\'status\');\n\n        if (status == \'Completed\') {\n            EventBus.publish(new DocuSign_Signed__e(\n                Envelope_Id__c = envelopeId\n            ));\n        }\n    }\n}\n\n// Subscriber trigger runs in system context â€” bypasses Guest FLS\ntrigger DocuSignSignedHandler on DocuSign_Signed__e (after insert) {\n    Set<String> ids = new Set<String>();\n    for (DocuSign_Signed__e e : Trigger.new) ids.add(e.Envelope_Id__c);\n    List<Contract> updates = [SELECT Id FROM Contract\n                              WHERE DocuSign_Envelope_Id__c IN :ids];\n    for (Contract c : updates) c.Status = \'Signed\';\n    update updates;\n}';
e11.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e11c1 };
entries.add(e11);

// ===== 12. MuleSoft Auth Setup â€” External Client App + 3-Email Matrix =====
NotionPublishService.StarEntry e12 = new NotionPublishService.StarEntry();
e12.title = '12. MuleSoft Auth Setup â€” External Client App + 3-Email Matrix';
e12.situation = 'MuleSoft needs OAuth credentials to call Salesforce. Classic Connected App creation was blocked on our Salesforce Dev org (security policy mandating new External Client App for new integrations). Three different Anypoint accounts existed for org reasons. PKCE blocked username-password OAuth flow Mule requires.';
e12.taskText = 'Get MuleSoft Anypoint Studio connecting to Salesforce successfully without PKCE blocking the username-password flow, working through the External Client App API rather than legacy Connected App.';
e12.actions = new List<String>{
    'Created External Client App in SF Setup (Setup â†’ External Client Apps, NOT Connected Apps) â€” different URL path',
    'Built 3-email role matrix: admin@technostore.example = OAuth runtime user, anypoint-admin@technostore.example = Anypoint admin, demo@technostore.example = ECA contact only (cannot log in)',
    'Disabled PKCE for Mule username-password flow â€” required because Mule HTTP Connector does not support PKCE challenge/verifier',
    'Whitelisted Anypoint EU region IP range in Salesforce Network Access â€” token endpoint was rejecting Mule IPs',
    'Verified token refresh works for 24h Anypoint Studio sessions without prompting for re-login'
};
e12.result = 'Mule Anypoint Studio polls SF via OAuth, no PKCE rejection. Token refresh smoothly handles 24h sessions. Three-email matrix avoids the single-account auth bottleneck. Pattern documented in mulesoft_integration_setup.md memory.';
NotionPublishService.CodeSnippet e12c1 = new NotionPublishService.CodeSnippet();
e12c1.caption = 'Mule SF connector OAuth config';
e12c1.language = 'xml';
e12c1.code = '<sfdc:config name="Salesforce_Config">\n    <sfdc:oauth-username-password\n        consumerKey="${sf.client.id}"\n        consumerSecret="${sf.client.secret}"\n        username="${sf.username}"\n        password="${sf.password}${sf.security.token}"\n        tokenEndpoint="https://login.salesforce.com/services/oauth2/token"/>\n</sfdc:config>\n\n<!-- mule-app.properties (gitignored) -->\nsf.client.id=3MVG9... (External Client App consumer key)\nsf.client.secret=...\nsf.username=admin@technostore.example\nsf.password=...\nsf.security.token=...';
e12.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e12c1 };
entries.add(e12);

// ===== 13. Stripe Payment Intent Creation =====
NotionPublishService.StarEntry e13 = new NotionPublishService.StarEntry();
e13.title = '13. Stripe Payment Intent Creation via MuleSoft';
e13.situation = 'After Order activation TechnoStore must send a payment link to the customer. Stripe API requires server-side PaymentIntent creation â€” secret key never touches client. Need Salesforce â†’ Mule â†’ Stripe path that returns a hosted payment URL to embed in customer email.';
e13.taskText = 'Build a Mule flow that takes Order amount/currency from Salesforce â†’ creates Stripe PaymentIntent â†’ returns hosted payment page URL embedded in branded invoice email.';
e13.actions = new List<String>{
    'Built Mule HTTP request to api.stripe.com/v1/payment_intents (form-encoded as Stripe API requires not JSON)',
    'Authenticated via STRIPE_SECRET_KEY in mule-app.properties (gitignored, kept out of repo)',
    'Mapped Salesforce Order.TotalAmount Ã— 100 (Stripe uses cents) + currency=EUR + customer email from Order.BillToContact',
    'Returned client_secret + Stripe-hosted payment page URL to SF via Mule response',
    'Salesforce embedded URL in AttachAndEmailInvoicePreview action â€” orange branded INVOICE PDF + payment link sent to customer'
};
e13.result = 'Order activation kicks off Mule call to Stripe. Customer receives email within 5 seconds with branded invoice PDF + "Pay Now" button linking to Stripe-hosted page. Stripe handles SCA, 3D Secure, card storage â€” TechnoStore handles only the orchestration. Pattern in technostore_branded_pdf_email_system.md memory.';
NotionPublishService.CodeSnippet e13c1 = new NotionPublishService.CodeSnippet();
e13c1.caption = 'Mule DataWeave transform for Stripe payload';
e13c1.language = 'xml';
e13c1.code = '<ee:transform>\n    <ee:message>\n        <ee:set-payload><![CDATA[%dw 2.0\noutput application/x-www-form-urlencoded\n---\n{\n    amount: (payload.TotalAmount * 100) as Number {format: "#"},\n    currency: "eur",\n    "automatic_payment_methods[enabled]": true,\n    receipt_email: payload.BillToContact.Email,\n    description: "TechnoStore Order " ++ payload.OrderNumber,\n    "metadata[order_id]": payload.Id,\n    "metadata[account_name]": payload.Account.Name\n}]]></ee:set-payload>\n    </ee:message>\n</ee:transform>\n\n<http:request method="POST"\n    url="https://api.stripe.com/v1/payment_intents"\n    config-ref="Stripe_HTTP">\n    <http:headers>#[{"Authorization": "Bearer " ++ p(\'stripe.secret.key\')}]</http:headers>\n</http:request>';
e13.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e13c1 };
entries.add(e13);

// ===== 14. Stripe Webhook Receiving =====
NotionPublishService.StarEntry e14 = new NotionPublishService.StarEntry();
e14.title = '14. Stripe Webhook Receiving â€” Payment Confirmation Loop';
e14.situation = 'After customer pays via Stripe-hosted page, Salesforce needs to know payment succeeded to fire receipt email + flip Order to Paid + trigger Asset creation. Stripe publishes payment_intent.succeeded event to webhook URL â€” Mule needs to receive, verify signature, fan out updates.';
e14.taskText = 'Receive Stripe webhook in Mule, verify webhook signature using STRIPE_WEBHOOK_SECRET, update Salesforce Order to Paid, fire receipt notification email + Slack notification.';
e14.actions = new List<String>{
    'Built Mule HTTP listener at https://<ngrok-url>/stripe/webhook receiving Stripe Connect events',
    'Verified webhook signature using STRIPE_WEBHOOK_SECRET (whsec_* â€” gitignored)',
    'Parsed Stripe event payload extracting metadata.order_id mapped back from PaymentIntent creation',
    'Salesforce update via salesforce:upsert connector with Order.Status=Paid + Order.Stripe_Payment_Id__c',
    'Fan-out: triggered EmailWithBrandedPdf flow for green branded RECEIPT PDF + posted to Slack #payments-team'
};
e14.result = 'Customer pays â†’ 2-3 seconds later: (1) Order.Status=Paid in SF, (2) green branded receipt PDF emailed, (3) Slack #payments-team notified. Close-the-loop pipeline complete. Two-stage PDF system: orange INVOICE pre-payment, green RECEIPT post-payment.';
NotionPublishService.CodeSnippet e14c1 = new NotionPublishService.CodeSnippet();
e14c1.caption = 'Mule webhook signature verification';
e14c1.language = 'xml';
e14c1.code = '<flow name="stripe-webhook">\n    <http:listener path="/stripe/webhook" config-ref="HTTP_Listener"/>\n\n    <!-- 1. Verify Stripe-Signature header -->\n    <ee:transform>\n        <ee:variables>\n            <ee:set-variable variableName="signed">\n                #[Crypto::HMACBinary(\n                    p(\'stripe.webhook.secret\') as Binary,\n                    (attributes.headers["stripe-signature"].timestamp ++ "." ++ payload) as Binary,\n                    "HmacSHA256"\n                )]\n            </ee:set-variable>\n        </ee:variables>\n    </ee:transform>\n\n    <choice>\n        <when expression="#[vars.expectedSig == attributes.headers[\'stripe-signature\'].v1]">\n            <!-- 2. Update SF Order to Paid -->\n            <sfdc:upsert objectType="Order" externalIdFieldName="Stripe_Payment_Id__c"/>\n            <!-- 3. Fan-out: email + Slack -->\n        </when>\n        <otherwise>\n            <http:response statusCode="400"/>\n        </otherwise>\n    </choice>\n</flow>';
e14.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e14c1 };
entries.add(e14);

// ===== Publish all =====
Integer success = 0;
Integer failed = 0;
List<String> failures = new List<String>();
for (Integer i = 0; i < entries.size(); i++) {
    NotionPublishService.StarEntry e = entries.get(i);
    try {
        String pageId = NotionPublishService.publish(e);
        System.debug('âœ… [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' â†’ ' + pageId);
        success++;
    } catch (Exception ex) {
        System.debug('âŒ [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' â€” ' + ex.getMessage());
        failed++;
        failures.add(e.title + ': ' + ex.getMessage());
    }
}
System.debug('=== BATCH 2 COMPLETE === Success: ' + success + ' / Failed: ' + failed);
for (String f : failures) System.debug('FAIL: ' + f);
