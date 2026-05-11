// Enterprise STAR entries 35-36: Slack #payments-team + #warehouse

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 35. Slack #payments-team Notifications ============
NotionPublishService.EnterpriseEntry e35 = new NotionPublishService.EnterpriseEntry();
e35.title = '35. Slack #payments-team — Real-Time Payment Notifications via Block Kit';
e35.situation = new NotionPublishService.SituationSection();
e35.situation.context = 'TechnoStore\'s finance operations team monitors incoming payments in real time. Stripe Dashboard requires Stripe-org credentials that not every finance user has provisioned, and Stripe email notifications create inbox noise. Slack #payments-team is the standard finance-ops channel for cross-functional visibility into payment events. The integration target: Stripe payment_intent.succeeded webhook → Mule → Slack incoming webhook → block-kit-formatted message in #payments-team within 3 seconds.';
e35.situation.problem = 'Plain text Slack messages do not provide structured information for finance review — recipient cannot quickly scan "amount / customer / payment method / order ID" without parsing prose. Slack Block Kit (the JSON-based structured-message format) provides section blocks + field grids + action buttons that render natively in Slack. Constructing valid Block Kit JSON requires understanding the block schema (section / divider / actions / fields), the mrkdwn vs plain_text type discriminator, and the URL action button format for "View in Salesforce" deep linking.';
e35.task = new NotionPublishService.TaskSection();
e35.task.goal = 'Wire Stripe payment_intent.succeeded webhook (entry 31) → Mule branch flow → Slack incoming webhook posting block-kit-formatted notification to #payments-team. Message must include customer name, amount in EUR, payment method, Salesforce Order ID with clickable "View in Salesforce" deep link. Zero email noise — finance team sees only Slack notifications.';
e35.task.constraints = 'Slack incoming webhook URLs are channel-specific (separate URL per channel for security). Slack rate limit: 1 message/second per webhook (TechnoStore demo volume well under limit). Block Kit type discriminator: section blocks use "text" with "type":"mrkdwn"; field grids use "fields" array with 2-column layout. Action buttons use "actions" block with "elements" array containing button objects with "url" property. SLACK_PAYMENTS_WEBHOOK_URL stored in mule-app.properties (gitignored — webhook URLs are secrets that grant write access).';
e35.task.successCriteria = 'Customer pays via Stripe → Stripe webhook fires → Mule branch flow constructs Block Kit JSON → POSTs to SLACK_PAYMENTS_WEBHOOK_URL → message appears in #payments-team within 3 seconds. Message renders: "✅ Payment Received — Hamburg DataWorks" header, 4-field grid (Amount / Order / Payment ID / Method), "View in Salesforce" button linking to SF Order page. Finance team scans 10+ payments per day in 30 seconds via Slack.';
e35.action = new NotionPublishService.ActionSection();
e35.action.approach = 'Built dedicated Mule sub-flow slack-payments-notify.xml invoked from the Stripe webhook fan-out (entry 31). DataWeave transform constructs Block Kit JSON from Stripe event payload + SF Account lookup. HTTP POST to SLACK_PAYMENTS_WEBHOOK_URL with Content-Type: application/json. Block Kit validated via Slack Block Kit Builder tool (api.slack.com/block-kit-builder) before Mule deployment.';
e35.action.implementation = new List<String>{
    'Created Slack workspace channel #payments-team via Slack Admin: Channel name=payments-team, Visibility=Private, Topic="Real-time payment notifications from TechnoStore Stripe integration"',
    'Created Slack App "TechnoStore Notifications" via api.slack.com/apps → Incoming Webhooks → New Webhook → channel=#payments-team → captured webhook URL (https://hooks.slack.com/services/T.../B.../...)',
    'Stored webhook URL in mule-app.properties as slack.payments.webhook.url=<value> (gitignored — webhook URLs grant write-only access to specific channel)',
    'Built Mule sub-flow slack-payments-notify.xml invoked from stripe-webhook-receive flow (entry 31) on payment_intent.succeeded events',
    'DataWeave transform constructs Block Kit JSON: section block with mrkdwn header "✅ Payment Received — {Account.Name}", divider block, section block with fields grid (Amount / Order / Payment ID / Method), actions block with View in Salesforce button',
    'Block Kit validated via api.slack.com/block-kit-builder before Mule deploy — pasted JSON, confirmed visual rendering, captured the validated payload',
    'HTTP POST to slack.payments.webhook.url with Content-Type: application/json, body = constructed Block Kit JSON',
    'View in Salesforce button URL: ${sf.org.url}/${payload.metadata.order_id} — deep links to the Order page using the Salesforce org URL from properties + the Stripe metadata.order_id captured during PaymentIntent creation (entry 30)',
    'Verified rendering: paid test order, Slack message appeared in #payments-team within 3 seconds with correct customer name, amount, button rendered with TechnoStore orange #FF6B00 styling',
    'Tested rate limit: triggered 5 payments in 5 seconds → Slack delivered all 5 messages without throttling (well under 1 msg/sec limit)',
    'Confirmed click-through: finance user clicked View in Salesforce button → opened SF Order record in browser with full context'
};
NotionPublishService.CodeSnippet e35c1 = new NotionPublishService.CodeSnippet();
e35c1.caption = 'Slack Block Kit JSON payload (DataWeave)';
e35c1.language = 'xml';
e35c1.code = '<flow name="slack-payments-notify">\n    <!-- Triggered from stripe-webhook-receive fan-out -->\n\n    <ee:transform doc:name="Block Kit message">\n        <ee:message>\n            <ee:set-payload><![CDATA[%dw 2.0\noutput application/json\n\nvar amount = (payload.data.object.amount / 100) as Number {format: "#,##0.00"}\nvar currency = upper(payload.data.object.currency)\nvar customerName = payload.data.object.metadata.account_name default "Unknown Customer"\nvar orderNumber = payload.data.object.metadata.order_number\nvar orderId = payload.data.object.metadata.order_id\nvar paymentId = payload.data.object.id\nvar paymentMethod = payload.data.object.charges.data[0].payment_method_details.type default "Card"\n\n---\n{\n    blocks: [\n        {\n            type: "section",\n            text: {\n                type: "mrkdwn",\n                text: "✅ *Payment Received* — " ++ customerName\n            }\n        },\n        {\n            type: "divider"\n        },\n        {\n            type: "section",\n            fields: [\n                { type: "mrkdwn", text: "*Amount:*\\n" ++ currency ++ " " ++ amount },\n                { type: "mrkdwn", text: "*Order:*\\n" ++ orderNumber },\n                { type: "mrkdwn", text: "*Payment ID:*\\n`" ++ paymentId ++ "`" },\n                { type: "mrkdwn", text: "*Method:*\\n" ++ paymentMethod }\n            ]\n        },\n        {\n            type: "actions",\n            elements: [\n                {\n                    type: "button",\n                    text: { type: "plain_text", text: "View in Salesforce" },\n                    url: p(\'sf.org.url\') ++ "/" ++ orderId,\n                    style: "primary"\n                }\n            ]\n        },\n        {\n            type: "context",\n            elements: [\n                {\n                    type: "mrkdwn",\n                    text: ":technostore: TechnoStore Order Fulfillment Pipeline | " ++ (now() as String)\n                }\n            ]\n        }\n    ]\n}]]></ee:set-payload>\n        </ee:message>\n    </ee:transform>\n\n    <http:request method="POST"\n        url="${slack.payments.webhook.url}"\n        config-ref="HTTP_Request_Slack">\n        <http:headers>#[{ "Content-Type": "application/json" }]</http:headers>\n    </http:request>\n</flow>';
e35.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e35c1 };
e35.result = new NotionPublishService.ResultSection();
e35.result.outcome = 'Customer pays → finance team sees "✅ Payment Received — Hamburg DataWorks / EUR 1,499.00 / Order 00000120 / Card" structured Block Kit message in #payments-team within 3 seconds. Click View in Salesforce → opens SF Order page directly. Zero email noise. Finance team scans 10+ daily payments in under 30 seconds. Demo recording shows the real-time loop: pay → Slack notification → SF drill-down — visible end-to-end orchestration.';
e35.result.tradeoffsAndLessons = 'Slack Block Kit is more verbose than plain text but dramatically improves scanning speed for ops teams. The Block Kit Builder tool (api.slack.com/block-kit-builder) is essential for visual iteration — paste JSON, see rendered output, adjust without round-tripping through Slack. Channel-specific webhook URLs are a security feature (one URL → one channel → no privilege escalation), but they require separate webhook setup per channel (one for #payments-team, one for #warehouse in entry 36). The metadata-passthrough pattern (Stripe metadata.order_id → SF deep link) is the canonical way to maintain CRM traceability through external systems.';
e35.result.references = new List<String>{
    'src/main/mule/flows/slack-payments-notify.xml',
    'Slack Block Kit Builder: api.slack.com/block-kit-builder',
    'Slack Incoming Webhooks: api.slack.com/messaging/webhooks',
    'mule-app.properties: slack.payments.webhook.url (gitignored)',
    'Stripe metadata.order_id pattern (entry 30) — traceability hook'
};
e35.result.futureWork = 'Add interactive buttons (Approve / Investigate / Mark Suspicious) using Slack Interactivity + Slash Commands — requires Slack App with OAuth scopes + URL endpoint for action callbacks. Currently the View in Salesforce button is the only interactive element. Production fraud-review workflow would use the interactive buttons.';
entries.add(e35);

// ============ 36. Slack #warehouse Approval Routing ============
NotionPublishService.EnterpriseEntry e36 = new NotionPublishService.EnterpriseEntry();
e36.title = '36. Slack #warehouse — Inventory Approval Routing via Platform Event Subscriber';
e36.situation = new NotionPublishService.SituationSection();
e36.situation.context = 'TechnoStore\'s warehouse operations team requires real-time notification when an Order is activated and ready for physical stock verification. The #warehouse Slack channel is the dedicated operations channel — separate from #payments-team (finance) to preserve channel scope and avoid cross-functional notification spam. Each Order activation publishes an Inventory_Check_Requested__e Platform Event in Salesforce; Mule subscribes via salesforce:replay-stream and routes to Slack #warehouse with a deep link to the custom approval VF page.';
e36.situation.problem = 'Salesforce Platform Events are the event-driven primitive for cross-system fan-out — Mule\'s salesforce:replay-stream connector subscribes to the Platform Event channel and receives events as they\'re published. Without proper replay configuration, Mule misses events during downtime (the default replayId=-1 starts from now, missing past events; replayId=-2 starts from beginning, replays history). For demo reliability, replayId=-1 is correct (no history replay), but the subscriber must handle the case where Mule is briefly down and a Platform Event fires during the gap.';
e36.task = new NotionPublishService.TaskSection();
e36.task.goal = 'Build Mule sub-flow that subscribes to Salesforce Platform Event /event/Inventory_Check_Requested__e channel via salesforce:replay-stream, transforms event payload to Slack Block Kit format with deep link to /apex/WarehouseInventoryApproval?id=<orderId>, posts to #warehouse Slack webhook within 3 seconds of event publish.';
e36.task.constraints = 'Salesforce Platform Event channel name format: /event/Inventory_Check_Requested__e (forward slash + event prefix + sObject API name). Mule salesforce:replay-stream requires replayId parameter: -1 (current, default), -2 (replay from earliest available, 24-hour retention), or specific replay ID for resume-after-downtime. Deep link must include the Salesforce org URL prefix from properties + the VF page path with id= query parameter. Slack webhook URL is channel-specific (different from #payments-team webhook).';
e36.task.successCriteria = 'Order activation in Salesforce → Inventory_Check_Requested__e Platform Event published with OrderId + AccountName + TotalAmount + ApprovalUrl fields → Mule subscriber receives within 1 second → Mule transforms to Block Kit JSON → POSTs to SLACK_WAREHOUSE_WEBHOOK_URL → message appears in #warehouse with "📦 Stock check needed" header + Order details + "Approve / Reject Stock" button linking to VF approval page. Warehouse user clicks → custom VF page opens → marks In/Out Stock.';
e36.action = new NotionPublishService.ActionSection();
e36.action.approach = 'Built warehouse-inventory-notify.xml Mule flow with salesforce:subscribe-channel-listener source pointing at /event/Inventory_Check_Requested__e channel with replayId=-1 (current). DataWeave transform reshapes the Platform Event payload (custom fields with __c suffix) into Block Kit JSON. HTTP POST to SLACK_WAREHOUSE_WEBHOOK_URL with the structured message + deep link to VF page. WarehouseInventoryApproval VF page hosts the approval UI (entry 38).';
e36.action.implementation = new List<String>{
    'Created Slack channel #warehouse via Slack Admin: Channel name=warehouse, Visibility=Private, Topic="Real-time inventory approval requests from TechnoStore Order Activation pipeline"',
    'Created separate Slack incoming webhook for #warehouse (cannot reuse #payments-team webhook — channel-specific): captured URL https://hooks.slack.com/services/.../.../...',
    'Stored webhook URL in mule-app.properties: slack.warehouse.webhook.url=<value> (gitignored, distinct from payments webhook)',
    'Built warehouse-inventory-notify.xml flow with source: <sfdc:subscribe-channel-listener streamingChannel="/event/Inventory_Check_Requested__e" config-ref="Salesforce_Config" replayId="-1"/>',
    'replayId=-1 chosen over -2: do NOT replay 24-hour history at startup, only consume events from current moment onwards (avoids re-sending old notifications on Mule restart)',
    'DataWeave transform reshapes Platform Event payload: payload.OrderId__c (custom field with __c suffix per SF metadata convention) → message includes OrderId, AccountName__c → customer name, TotalAmount__c → amount, ApprovalUrl__c → deep link',
    'Block Kit message structure: section block with "📦 *Stock check needed*" header + fields grid (Order / Customer / Amount) + actions block with "Approve / Reject Stock" button URL = payload.ApprovalUrl__c',
    'ApprovalUrl__c value is constructed by the OrderTriggerHandler when publishing the Platform Event (entry 9): System.URL.getOrgDomainUrl().toExternalForm() + \'/apex/WarehouseInventoryApproval?id=\' + Order.Id',
    'Tested with Postman publishing test Platform Event via Salesforce REST API → Mule subscriber received within 1 second → Slack message in #warehouse within 3 seconds',
    'Verified end-to-end: Order activated in Salesforce → Platform Event published → Mule consumed → Slack notification arrived → warehouse user clicked button → VF page loaded → Mark In Stock button visible',
    'Documented full Platform Event → Slack pipeline in inventory_approval_warehouse_flow.md memory'
};
NotionPublishService.CodeSnippet e36c1 = new NotionPublishService.CodeSnippet();
e36c1.caption = 'Platform Event subscriber + Slack deep link (Mule)';
e36c1.language = 'xml';
e36c1.code = '<flow name="warehouse-inventory-notify">\n    <!-- Source: subscribe to SF Platform Event channel -->\n    <sfdc:subscribe-channel-listener\n        config-ref="Salesforce_Config"\n        streamingChannel="/event/Inventory_Check_Requested__e"\n        replayId="-1"/>\n\n    <!-- Block Kit message with deep link to custom VF page -->\n    <ee:transform doc:name="Warehouse Block Kit message">\n        <ee:message>\n            <ee:set-payload><![CDATA[%dw 2.0\noutput application/json\n---\n{\n    text: "📦 Stock check needed",  // fallback for plain-text notifications\n    blocks: [\n        {\n            type: "section",\n            text: {\n                type: "mrkdwn",\n                text: "📦 *Stock Check Required* — Order Activation Pipeline"\n            }\n        },\n        {\n            type: "section",\n            fields: [\n                { type: "mrkdwn", text: "*Order:*\\n" ++ payload.OrderId__c },\n                { type: "mrkdwn", text: "*Customer:*\\n" ++ payload.AccountName__c },\n                { type: "mrkdwn", text: "*Amount:*\\n€" ++ (payload.TotalAmount__c as String) },\n                { type: "mrkdwn", text: "*Status:*\\nAwaiting Warehouse Approval" }\n            ]\n        },\n        {\n            type: "actions",\n            elements: [\n                {\n                    type: "button",\n                    text: { type: "plain_text", text: "Approve / Reject Stock", emoji: true },\n                    url: payload.ApprovalUrl__c,  // /apex/WarehouseInventoryApproval?id=...\n                    style: "primary",\n                    action_id: "open_approval_page"\n                }\n            ]\n        },\n        {\n            type: "context",\n            elements: [\n                {\n                    type: "mrkdwn",\n                    text: "Published from Salesforce Platform Event channel /event/Inventory_Check_Requested__e | " ++ (now() as String)\n                }\n            ]\n        }\n    ]\n}]]></ee:set-payload>\n        </ee:message>\n    </ee:transform>\n\n    <http:request method="POST"\n        url="${slack.warehouse.webhook.url}"\n        config-ref="HTTP_Request_Slack">\n        <http:headers>#[{ "Content-Type": "application/json" }]</http:headers>\n    </http:request>\n</flow>';
e36.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e36c1 };
e36.result = new NotionPublishService.ResultSection();
e36.result.outcome = 'Order activated → Inventory_Check_Requested__e Platform Event published in SF → Mule subscriber receives within 1 second → Slack #warehouse notification arrives within 3 seconds with deep link to custom VF approval page. Warehouse user clicks → VF page opens with Mark In/Out Stock buttons → user marks stock outcome → Order.Inventory_Status__c updated in SF. Separation of duties enforced: Sales activates Order (one role), Operations approves stock (different role + different channel + different UI).';
e36.result.tradeoffsAndLessons = 'Salesforce Platform Events are the right primitive for cross-system fan-out events that need (a) guaranteed delivery, (b) replay support, (c) decoupling from synchronous transaction context. Mule\'s salesforce:replay-stream connector handles the CometD/Streaming API subscription complexity transparently. replayId=-1 vs -2 trade-off: -1 misses events during Mule downtime but avoids re-delivery on restart; -2 captures everything but risks duplicates. For demo, -1 is the right call; for production with strict SLAs, persist last-processed-replayId in Mule state and resume from there.';
e36.result.references = new List<String>{
    'src/main/mule/flows/warehouse-inventory-notify.xml',
    'force-app/main/default/objects/Inventory_Check_Requested__e/ (Platform Event definition)',
    'Memory: inventory_approval_warehouse_flow.md (full pipeline)',
    'WarehouseInventoryApproval VF page (entry 38)',
    'Mule salesforce:replay-stream connector documentation'
};
e36.result.futureWork = 'Add persistent last-processed-replayId tracking via Mule Object Store v2 — enables exact-resume after Mule downtime without duplicates. Currently a 30-second Mule outage loses any Platform Events fired during that window; production version would store replayId per processed event and pass it on next subscription.';
entries.add(e36);

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
System.debug('=== BATCH 12 COMPLETE (entries 35-36) === Success: ' + success + ' / Failed: ' + failed);
