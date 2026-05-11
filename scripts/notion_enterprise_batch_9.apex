// Enterprise STAR entries 28-30: DocuSign webhook + native investigation + Stripe

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 28. DocuSign Inbound Webhook ============
NotionPublishService.EnterpriseEntry e28 = new NotionPublishService.EnterpriseEntry();
e28.title = '28. DocuSign Inbound Webhook — Salesforce Site + Guest User + Platform Event Indirection';
e28.situation = new NotionPublishService.SituationSection();
e28.situation.context = 'When the customer completes the DocuSign signing process (clicks Sign Here on the Anchor Tab), DocuSign publishes a Connect event via webhook POST to a configured public URL. The Contract.Status in Salesforce must auto-flip from Awaiting Signature → Signed without manual intervention. DocuSign Connect is the inbound side of the bidirectional integration (outbound side documented in entry 27).';
e28.situation.problem = 'DocuSign Connect requires a publicly-reachable webhook URL — internal Salesforce REST endpoints behind login are not accessible. Salesforce Site (force.com/yourdomain) provides a public surface but the Guest User context has restrictive FLS: cannot directly UPDATE Contract.Status (standard fields on standard objects are blocked for Guest profiles by default). Attempting to give Guest User Contract.Status FLS via permission set violates Salesforce security recommendations and may not work for all standard fields.';
e28.task = new NotionPublishService.TaskSection();
e28.task.goal = 'Build an inbound webhook on a Salesforce Site receiving DocuSign Connect events, parse the envelopeId + envelope status, propagate to Contract.Status update via Platform Event indirection (Guest User publishes Platform Event → trigger subscriber runs in system context with full FLS → updates Contract.Status).';
e28.task.constraints = 'Salesforce Site Guest User profile cannot directly DML Contract.Status (FLS restriction). Platform Events are publishable by Guest User (separate permission, easier to grant). Apex trigger subscribers on Platform Events run in system context (full FLS, bypass sharing) — this is the documented indirection pattern. DocuSign Connect retries failed deliveries with exponential backoff, so webhook handler must be idempotent (multiple deliveries of same event must not flip Contract.Status more than once).';
e28.task.successCriteria = 'Customer signs DocuSign envelope → DocuSign Connect fires webhook POST to Salesforce Site URL within 30 seconds → DocuSignWebhookController receives event → Platform Event DocuSign_Signed__e published → trigger subscriber updates Contract.Status to Signed → end-to-end latency under 60 seconds. Idempotent on retry: re-delivery of same envelope event does NOT cause double-update.';
e28.action = new NotionPublishService.ActionSection();
e28.action.approach = 'Created Salesforce Site /docusign_webhook with Guest User access. Built DocuSignWebhookController as @RestResource exposing @HttpPost endpoint. Webhook parses DocuSign Connect XML/JSON payload, extracts envelopeId + status, publishes DocuSign_Signed__e Platform Event. Trigger DocuSignSignedHandler on the Platform Event runs in system context, queries Contract by DocuSign_Envelope_Id__c = envelopeId, updates Contract.Status if not already Signed.';
e28.action.implementation = new List<String>{
    'Created Salesforce Site via Setup -> Sites -> New Site: Site Label=DocuSign Webhook, Default Web Address=docusign-webhook, Active=true',
    'Configured Site Guest User: profile = DocuSign Webhook Guest User (cloned from Standard Guest User), granted Platform Event Publish permission for DocuSign_Signed__e, no Contract object access (intentional — Guest cannot touch Contract directly)',
    'Created Platform Event DocuSign_Signed__e with fields: Envelope_Id__c (Text 255), Envelope_Status__c (Text 50), Signed_At__c (DateTime). Deploy=true, PublishBehavior=PublishImmediately',
    'Built DocuSignWebhookController.cls as @RestResource(urlMapping=\'/docusign_webhook/*\') with @HttpPost method receiveSignedEvent()',
    'Webhook handler reads RestContext.request.requestBody, parses as JSON, extracts envelopeStatus + envelopeId, validates against DOCUSIGN_HMAC signature header (verifies request origin)',
    'On envelope status = Completed: publishes DocuSign_Signed__e Platform Event with Envelope_Id__c=envelopeId + Envelope_Status__c=Completed + Signed_At__c=now',
    'Built DocuSignSignedHandler trigger on DocuSign_Signed__e Platform Event channel — runs in system context, queries Contract.Id WHERE DocuSign_Envelope_Id__c IN :ids AND Status != \'Signed\', updates Contract.Status=Signed',
    'Configured DocuSign Connect: Account Setup -> Integrations -> Connect -> Add Configuration: URL=https://your-org.my.site.com/docusign_webhook/v1/notify, HMAC Secret=stored in DocuSign_Config__c.HMAC_Secret__c, Event Triggers=Completed/Declined/Voided',
    'Idempotency guard: Status != \'Signed\' filter prevents double-update on DocuSign retry',
    'Tested end-to-end: signed test envelope → webhook fired within 30 seconds → Platform Event published → trigger fired in <1s → Contract.Status=Signed visible in Salesforce. Total latency: ~35 seconds'
};
NotionPublishService.CodeSnippet e28c1 = new NotionPublishService.CodeSnippet();
e28c1.caption = 'DocuSignWebhookController.cls + Platform Event subscriber';
e28c1.language = 'java';
e28c1.code = '// force-app-controllers/main/default/classes/DocuSignWebhookController.cls\n@RestResource(urlMapping=\'/docusign_webhook/*\')\nglobal with sharing class DocuSignWebhookController {\n\n    @HttpPost\n    global static void receiveSignedEvent() {\n        RestResponse resp = RestContext.response;\n        try {\n            String body = RestContext.request.requestBody.toString();\n\n            // HMAC verification against DocuSign-supplied signature header\n            String suppliedHmac = RestContext.request.headers.get(\'X-DocuSign-Signature-1\');\n            if (!verifyHmac(body, suppliedHmac)) {\n                resp.statusCode = 401;\n                resp.responseBody = Blob.valueOf(\'Invalid HMAC signature\');\n                return;\n            }\n\n            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);\n            Map<String, Object> envelopeStatus = (Map<String, Object>) payload.get(\'envelopeStatus\');\n            String envelopeId = (String) envelopeStatus.get(\'envelopeId\');\n            String status = (String) envelopeStatus.get(\'status\');\n\n            if (status == \'Completed\') {\n                EventBus.publish(new DocuSign_Signed__e(\n                    Envelope_Id__c = envelopeId,\n                    Envelope_Status__c = status,\n                    Signed_At__c = System.now()\n                ));\n            }\n            resp.statusCode = 200;\n            resp.responseBody = Blob.valueOf(\'OK\');\n        } catch (Exception e) {\n            resp.statusCode = 500;\n            resp.responseBody = Blob.valueOf(\'Error: \' + e.getMessage());\n        }\n    }\n\n    private static Boolean verifyHmac(String body, String suppliedHmac) {\n        // HMAC-SHA256 of body using DocuSign_Config__c.HMAC_Secret__c\n        DocuSign_Config__c cfg = DocuSign_Config__c.getOrgDefaults();\n        Blob mac = Crypto.generateMac(\'HmacSHA256\',\n                                       Blob.valueOf(body),\n                                       Blob.valueOf(cfg.HMAC_Secret__c));\n        String computedHmac = EncodingUtil.base64Encode(mac);\n        return computedHmac == suppliedHmac;\n    }\n}\n\n// force-app/main/default/triggers/DocuSignSignedHandler.trigger\ntrigger DocuSignSignedHandler on DocuSign_Signed__e (after insert) {\n    Set<String> envIds = new Set<String>();\n    for (DocuSign_Signed__e e : Trigger.new) envIds.add(e.Envelope_Id__c);\n\n    // Runs in system context — full FLS, bypass Guest restrictions\n    List<Contract> updates = [\n        SELECT Id, Status FROM Contract\n        WHERE DocuSign_Envelope_Id__c IN :envIds\n        AND Status != \'Signed\'   // idempotency guard\n    ];\n    for (Contract c : updates) c.Status = \'Signed\';\n    if (!updates.isEmpty()) update updates;\n}';
e28.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e28c1 };
e28.result = new NotionPublishService.ResultSection();
e28.result.outcome = 'Bidirectional DocuSign integration complete. Customer signs envelope → 30-second webhook delivery → Platform Event published by Guest User → trigger subscriber updates Contract.Status=Signed in system context. End-to-end Send-to-Signed cycle: rep clicks Send For Signature → 3 sec DocuSign envelope sent → customer signs (variable time) → 35 sec until Salesforce reflects Signed status. Full audit trail in EventBus + DocuSign envelope history. Idempotent on retry.';
e28.result.tradeoffsAndLessons = 'The Salesforce Site + Guest User + Platform Event indirection pattern is the canonical solution for Guest-User-cannot-write-to-Object problems. Guest User publishes Platform Events (separate permission, easy to grant); Platform Event trigger runs in system context (full FLS, bypass sharing). This pattern works for ANY inbound webhook needing internal record updates: DocuSign, Stripe, Slack, JIRA. HMAC signature verification (X-DocuSign-Signature-1 header) is critical for security — webhooks without HMAC verification are trivially spoofable. Pattern is reusable.';
e28.result.references = new List<String>{
    'force-app-controllers/main/default/classes/DocuSignWebhookController.cls',
    'force-app/main/default/objects/DocuSign_Signed__e/',
    'Salesforce Site /docusign_webhook setup',
    'Memory: docusign_integration_progress.md (full bidirectional)'
};
e28.result.futureWork = 'Generalize to a webhook framework: WebhookController base class with Crypto-based HMAC verification + Platform Event publishing helper. Subclasses for DocuSign / Stripe / Sendcloud / Slack inbound webhooks. Reduces boilerplate per new webhook integration from ~50 lines to ~10.';
entries.add(e28);

// ============ 29. DocuSign CLM Native Send — 7-Hypothesis Investigation ============
NotionPublishService.EnterpriseEntry e29 = new NotionPublishService.EnterpriseEntry();
e29.title = '29. DocuSign CLM Native Send — 7-Hypothesis Investigation + Build-Custom Decision';
e29.situation = new NotionPublishService.SituationSection();
e29.situation.context = 'Salesforce CLM ships a native Send for Signature button on Contract layout that integrates with DocuSign for Salesforce (the bundled connector). This button should pull the Contract PDF, populate signer details from Contract.BillToContact, and route the envelope to DocuSign — all in 2 clicks. The integration is positioned as "out-of-the-box" in Salesforce documentation.';
e29.situation.problem = 'Clicking the native CLM Send for Signature button on Contract did NOTHING visible to the user — no error message, no envelope created, no status change. Salesforce debug logs showed the button click was received but the underlying DocuSign Send action never completed. Initial assumption: something in our Contract setup was wrong. The investigation that followed eliminated 7 hypotheses before reaching the actual root cause, which turned out to be an INTENTIONAL Salesforce platform design decision (not a bug).';
e29.task = new NotionPublishService.TaskSection();
e29.task.goal = 'Diagnose why native CLM Send for Signature silently fails on our org. Determine if (a) the integration needs additional configuration, (b) DocuSign for Salesforce package is misconfigured, (c) Contract record is missing required fields, (d) the underlying Apex action has a platform-restricting precondition. After investigation, decide whether to fix native or build custom replacement.';
e29.task.constraints = 'Salesforce CLM Send for Signature is a black-box action — no public Apex API to inspect what it does. The button is bound to internal CLM machinery that does not surface execution logs in the standard Debug Log. DocuSign for Salesforce is a managed package — internal logic is not modifiable by the customer. Investigation must proceed through hypothesis-elimination, not source-code reading.';
e29.task.successCriteria = 'Root cause definitively identified and documented. Decision made on whether to fix native or build custom (entry 27). If fix is impossible, the build-custom path must be 100% reliable replacement covering same use case.';
e29.action = new NotionPublishService.ActionSection();
e29.action.approach = 'Systematic hypothesis-elimination over ~6 hours: tested 7 distinct hypotheses, each focused on a specific potentially-missing piece. Reviewed Salesforce official docs after eliminations exhausted obvious config issues. Final root cause discovered in CLM Signer Roles documentation: LegalName auto-fill is intentionally disabled for Signer-type recipients (Signer Name is meant to be blank at template-binding time per Salesforce-blessed design).';
e29.action.implementation = new List<String>{
    'Hypothesis 1: DocuSign for Salesforce package not installed → verified installed in Setup -> Installed Packages → ELIMINATED',
    'Hypothesis 2: DocuSign Connect not configured → verified Connect URL configured in DocuSign Admin → ELIMINATED',
    'Hypothesis 3: Contract.BillToContact missing → verified Contract has BillToContactId populated on every demo record → ELIMINATED',
    'Hypothesis 4: ESignatureConfig (Signer Roles) not configured → discovered missing! Created ESignatureConfig with ConfigType=SignerRoles + GroupType=AnchorTabSetting → still silent failure → PARTIALLY HELPFUL but not root cause',
    'Hypothesis 5: DocumentTemplate not bound to ESignatureConfig → verified binding exists via DocumentTemplate.ESignatureConfigId field → ELIMINATED',
    'Hypothesis 6: Salesforce profile lacks DocuSign permission set → assigned DocuSign User permission set to technostore-admin@example.com → still silent failure → ELIMINATED',
    'Hypothesis 7: Contract.Status not in the allowed state for Send action → checked CLM lifecycle docs: Status must be Approved before Send → moved Contract to Approved → still silent failure → ELIMINATED',
    'Final hypothesis (root cause): Read Salesforce CLM Signer Roles documentation deep dive. Discovered: "Signer Name field is intentionally LEFT BLANK at template binding time for Signer-type recipients. LegalName auto-fill is disabled BY DESIGN because the recipient is meant to populate Name when they sign." This is intentional Salesforce architecture, not a bug',
    'Salesforce-documented workaround: "Build your own Send UI" — exactly what we did in entry 27 with DocuSignSendService.cls. The custom path bypasses the native Signer Name auto-fill restriction entirely',
    'Decision: stop iterating on native (7+ hypotheses eliminated, root cause confirms it cannot be fixed via configuration). Build custom DocuSignSendService.cls + Send_For_Signature screen flow (entries 24 + 27). Native button removed from Contract layout',
    'Documented full 7-hypothesis investigation timeline in clm_native_send_for_signature_blocked.md memory for the next engineer who hits the same wall'
};
NotionPublishService.CodeSnippet e29c1 = new NotionPublishService.CodeSnippet();
e29c1.caption = 'ESignatureConfig setup (one of the partial-fixes during investigation)';
e29c1.language = 'java';
e29c1.code = '// ESignatureConfig was a partial fix during hypothesis 4 — does not resolve root cause\n// alone but is required for any custom or native DocuSign integration\n\nESignatureConfig esc = new ESignatureConfig(\n    Name = \'TechnoStore Signer Roles\',\n    ConfigType = \'SignerRoles\',\n    GroupType = \'AnchorTabSetting\',\n    ConfigValue = \'Buyer,Authorized Signer\',  // comma-separated role names\n    Status = \'Active\'\n);\ninsert esc;\n\n// Note: Apex DML on ESignatureConfig is sometimes blocked due to underlying metadata\n// restrictions — alternative is to deploy via SF CLI Metadata API:\n// sf project deploy start --source-dir force-app/main/default/eSignatureConfigs/...';
e29.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e29c1 };
e29.result = new NotionPublishService.ResultSection();
e29.result.outcome = 'Root cause identified after 7 hypothesis-elimination iterations: LegalName auto-fill is INTENTIONALLY disabled for Signer-type recipients per Salesforce-blessed design. Native CLM Send for Signature cannot be made to work via configuration alone — the "fix" Salesforce documents is "build your own Send UI". Decision: drop native, build custom DocuSignSendService.cls (entry 27) + Send_For_Signature screen flow (entry 24). Native button removed from Contract layout to avoid confusion. Demo runs 100% reliably via the custom replacement.';
e29.result.tradeoffsAndLessons = 'When a platform feature appears broken, "intentionally restricted by design" is a real category of root cause that documentation often does not surface clearly. The 6-hour 7-hypothesis investigation has value beyond this specific issue: the elimination process is documented for any future "native CLM action does nothing" investigation. Diagnostic pattern: always check Salesforce-documented architecture intent BEFORE assuming the issue is configuration. The build-custom path turned out to be ~4 hours of work but delivered 100% reliable behavior — net win vs. continuing to fight platform architecture.';
e29.result.references = new List<String>{
    'Memory: clm_native_send_for_signature_blocked.md (7-hypothesis investigation timeline)',
    'Salesforce CLM Signer Roles documentation (root cause source)',
    'Memory: clm_signer_roles_setup.md (ESignatureConfig recipe)',
    'force-app-services/main/default/classes/DocuSignSendService.cls (the working custom replacement)'
};
e29.result.futureWork = 'If Salesforce ever publishes a fix or workaround for native CLM Send (e.g., adding LegalName override config), re-evaluate the native path. Until then, custom DocuSignSendService is the production-grade pattern.';
entries.add(e29);

// ============ 30. Stripe Payment Intent Creation ============
NotionPublishService.EnterpriseEntry e30 = new NotionPublishService.EnterpriseEntry();
e30.title = '30. Stripe Payment Intent Creation — Mule HTTP Outbound + Form-Encoded Payload';
e30.situation = new NotionPublishService.SituationSection();
e30.situation.context = 'After Order activation, TechnoStore must send the customer a payment link. Stripe requires server-side PaymentIntent creation — the secret key cannot touch the browser. The standard pattern is: Salesforce Order activation triggers a Mule flow → Mule HTTP outbound to api.stripe.com/v1/payment_intents → Stripe returns client_secret + hosted payment page URL → Mule returns URL to Salesforce → Salesforce embeds URL in customer email.';
e30.situation.problem = 'Stripe API uses form-encoded POST payloads (application/x-www-form-urlencoded), NOT JSON. This is unusual for a modern API and trips up most developers expecting JSON. Numeric fields (amount) must be in cents (€10.00 → 1000 not 10.00). Currency must be lowercase 3-letter ISO (eur not EUR). Metadata fields use bracket notation (metadata[order_id]=abc) not nested JSON. Authentication is HTTP Basic with secret key as username + empty password — different from OAuth Bearer.';
e30.task = new NotionPublishService.TaskSection();
e30.task.goal = 'Build a Mule flow that consumes Salesforce Order data (TotalAmount + currency + BillToContact.Email + OrderNumber), constructs a Stripe-compatible form-encoded PaymentIntent payload, POSTs to api.stripe.com/v1/payment_intents, parses the response, returns the Stripe-hosted payment page URL + client_secret back to Salesforce for email embedding.';
e30.task.constraints = 'Stripe form-encoded payload: amount in CENTS as integer (no decimals), currency lowercase, automatic_payment_methods[enabled]=true, metadata fields use bracket notation. Authentication: Basic with secret key in username field, empty password — base64 the "sk_test_*:" string. Stripe secret key must be in mule-app.properties (gitignored — never committed). Mule DataWeave needs explicit output content-type set to application/x-www-form-urlencoded.';
e30.task.successCriteria = 'Salesforce Order activation → Mule flow consumes Order payload via HTTP → constructs Stripe form-encoded body → POST to api.stripe.com/v1/payment_intents → Stripe returns 200 with client_secret + payment URL → Mule returns URL to Salesforce → Salesforce email template embeds "Pay Now" button linking to Stripe hosted page → customer clicks → pays on Stripe-hosted page. End-to-end from activation to customer email under 10 seconds.';
e30.action = new NotionPublishService.ActionSection();
e30.action.approach = 'Built dedicated Mule flow stripe-create-paymentintent.xml triggered by HTTP POST from Salesforce. Used DataWeave transform with output application/x-www-form-urlencoded to construct the Stripe payload, mapping Salesforce Order fields to Stripe required fields. HTTP request to api.stripe.com/v1/payment_intents with Basic Auth header. Parsed JSON response (Stripe replies with JSON despite accepting form-encoded). Returned the payment URL to Salesforce as JSON response.';
e30.action.implementation = new List<String>{
    'Built Mule flow stripe-create-paymentintent.xml with HTTP Listener on /stripe/intent (accepts JSON from Salesforce containing Order Id + amount + currency + customer email + order number)',
    'DataWeave transform 1: parse Salesforce JSON input, validate fields (amount > 0, currency 3-letter ISO, email present)',
    'DataWeave transform 2: convert to Stripe form-encoded format with output application/x-www-form-urlencoded, multiply amount by 100 (Stripe cents), lowercase currency, add metadata[order_id] + metadata[account_name]',
    'HTTP Basic Auth header: "Authorization: Basic " + base64(p(\'stripe.secret.key\') + ":")',
    'HTTP request to https://api.stripe.com/v1/payment_intents with form-encoded body — Stripe responds with JSON containing id (PaymentIntent.Id), client_secret, next_action.redirect_to_url.url (hosted payment page)',
    'DataWeave transform 3: extract client_secret + payment URL, construct JSON response back to Salesforce',
    'Salesforce side: receive JSON response, store PaymentIntent.Id on Order.Stripe_Payment_Intent_Id__c, embed payment URL in AttachAndEmailInvoicePreview action (orange branded invoice PDF + Pay Now button)',
    'Tested end-to-end with a test Order (amount €1,499.00): Mule received SF call, constructed Stripe payload, Stripe returned PaymentIntent with hosted URL, customer email rendered with Pay Now button linking to Stripe-hosted page',
    'Stripe-hosted page handles SCA (Strong Customer Authentication), 3D Secure 2.0, card storage, payment retry — TechnoStore handles only orchestration',
    'Documented full integration in mulesoft_integration_setup.md memory with Stripe form-encoding gotchas highlighted'
};
NotionPublishService.CodeSnippet e30c1 = new NotionPublishService.CodeSnippet();
e30c1.caption = 'Mule DataWeave for Stripe form-encoded payload';
e30c1.language = 'xml';
e30c1.code = '<flow name="stripe-create-paymentintent">\n    <http:listener config-ref="HTTP_Listener_Config" path="/stripe/intent"/>\n\n    <!-- 1. Parse incoming Salesforce JSON -->\n    <ee:transform doc:name="Validate input">\n        <ee:message>\n            <ee:set-payload><![CDATA[%dw 2.0\noutput application/java\nvar input = payload\n---\n{\n    orderId: input.OrderId default \'\',\n    amount: input.TotalAmount as Number,\n    currency: lower(input.CurrencyIsoCode),\n    customerEmail: input.BillToContact.Email,\n    orderNumber: input.OrderNumber,\n    accountName: input.Account.Name\n}]]></ee:set-payload>\n        </ee:message>\n    </ee:transform>\n\n    <!-- 2. Convert to Stripe form-encoded format -->\n    <ee:transform doc:name="Stripe form-encoded">\n        <ee:message>\n            <ee:set-payload><![CDATA[%dw 2.0\noutput application/x-www-form-urlencoded\n---\n{\n    amount: (payload.amount * 100) as Number {format: "#"},\n    currency: payload.currency,\n    "automatic_payment_methods[enabled]": true,\n    receipt_email: payload.customerEmail,\n    description: "TechnoStore Order " ++ payload.orderNumber,\n    "metadata[order_id]": payload.orderId,\n    "metadata[account_name]": payload.accountName,\n    "metadata[order_number]": payload.orderNumber\n}]]></ee:set-payload>\n        </ee:message>\n    </ee:transform>\n\n    <!-- 3. POST to Stripe with Basic Auth -->\n    <http:request method="POST"\n        url="https://api.stripe.com/v1/payment_intents"\n        config-ref="HTTP_Request_Config_Stripe">\n        <http:headers>#[{\n            "Authorization": "Basic " ++ (p(\'stripe.secret.key\') ++ ":") as Binary write="application/x-www-form-urlencoded" base64Encode,\n            "Content-Type": "application/x-www-form-urlencoded"\n        }]</http:headers>\n    </http:request>\n\n    <!-- 4. Parse Stripe JSON response (note: Stripe responds JSON even though request was form-encoded) -->\n    <ee:transform doc:name="Extract payment URL">\n        <ee:message>\n            <ee:set-payload><![CDATA[%dw 2.0\noutput application/json\n---\n{\n    paymentIntentId: payload.id,\n    clientSecret: payload.client_secret,\n    paymentUrl: payload.next_action.redirect_to_url.url default ("https://checkout.stripe.com/c/pay/" ++ payload.client_secret)\n}]]></ee:set-payload>\n        </ee:message>\n    </ee:transform>\n</flow>';
e30.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e30c1 };
e30.result = new NotionPublishService.ResultSection();
e30.result.outcome = 'Stripe PaymentIntent creation works end-to-end from Salesforce Order activation. Mule flow consumes Order payload, calls Stripe API, returns PaymentIntent ID + hosted payment page URL to Salesforce within 4-5 seconds. Salesforce email template embeds the Stripe URL in a Pay Now button visible in the customer\'s branded INVOICE email. Customer clicks Pay Now → Stripe-hosted page handles SCA + 3D Secure + payment method storage. Stripe handles card vault, EU PSD2 compliance, fraud detection. TechnoStore handles only orchestration.';
e30.result.tradeoffsAndLessons = 'Stripe\'s form-encoded API contract is a 10-year-old design choice that surprises modern developers but works reliably once you accept it. The DataWeave transform for form-encoding (output application/x-www-form-urlencoded) is the canonical Mule pattern. Stripe Basic Auth with empty password is unusual but well-documented. The architectural separation (Stripe owns payment page + compliance, TechnoStore owns orchestration) is the right SaaS integration pattern for payments specifically.';
e30.result.references = new List<String>{
    'src/main/mule/flows/stripe-create-paymentintent.xml',
    'Stripe API v1 payment_intents documentation',
    'Memory: mulesoft_integration_setup.md',
    'AttachAndEmailInvoicePreview invocable action (Salesforce side)'
};
e30.result.futureWork = 'Add multi-currency support (CHF for Switzerland, USD for global customers) — Stripe supports 135+ currencies natively, just update Salesforce Order.CurrencyIsoCode and Mule passes it through. Subscription billing (Stripe Subscriptions API) is a future evolution if TechnoStore offers recurring service plans.';
entries.add(e30);

// ============ Publish ============
Integer success = 0;
Integer failed = 0;
for (Integer i = 0; i < entries.size(); i++) {
    NotionPublishService.EnterpriseEntry e = entries.get(i);
    try {
        String pageId = NotionPublishService.publishEnterprise(e);
        System.debug('OK [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' -> ' + pageId);
        success++;
    } catch (Exception ex) {
        System.debug('FAIL [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' - ' + ex.getMessage());
        failed++;
    }
}
System.debug('=== BATCH 9 COMPLETE (entries 28-30) === Success: ' + success + ' / Failed: ' + failed);
