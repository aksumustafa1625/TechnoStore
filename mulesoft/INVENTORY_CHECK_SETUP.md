# Inventory Check via Slack — Setup Guide

Same pattern as the existing payments-team flow: Salesforce publishes a Platform Event,
MuleSoft listens and posts a Block Kit message to Slack via an Incoming Webhook. **No ngrok,
no Slack App, no callbacks** — when the warehouse user wants to confirm, they open the
Salesforce Order page (linked in the Slack message) and click **Mark In Stock** or
**Mark Out of Stock**.

## Architecture

```
[Salesforce Order page]
    user clicks "Request Inventory Check"
            ↓
    Apex InventoryCheckService.requestCheck(orderId)
        publishes Inventory_Check_Requested__e
            ↓
[CometD streaming channel]
    /event/Inventory_Check_Requested__e
            ↓
[MuleSoft inventory-check-flow]
    salesforce:replay-channel-listener picks up the event,
    builds a Block Kit message,
    POSTs to ${slack.warehouse.webhook.path}
            ↓
[Slack #warehouse channel]
    message appears with order details + a link back to the SF Order
            ↓
[Warehouse manager]
    opens the SF link, clicks "Mark In Stock" or "Mark Out of Stock" quick action
            ↓
[Salesforce Order]
    Inventory_Status__c, Inventory_Confirmed_By__c, Inventory_Confirmed_At__c updated
```

## One-time setup (5 minutes)

### 1. Create `#warehouse` channel in Slack

In the TechnoStore Slack workspace, create a new channel named `#warehouse` (or whatever you
prefer — just remember the name).

### 2. Add an Incoming Webhook to `#warehouse`

Open the channel → channel name → **Integrations** tab → **Add an App** → search for
**Incoming Webhooks** → **Add to Slack** → pick the `#warehouse` channel → **Add Incoming
Webhooks Integration**.

Slack will show you a **Webhook URL**. Format: the Slack hooks host plus a path of the form
`/services/<workspace-id>/<channel-hook-id>/<token>` (workspace + channel + 24-char token).

Copy the **path portion only** (everything after the host) — that's the value to paste into
the Mule property.

### 3. Add the property to the Mule app

In Anypoint Studio, open `src/main/resources/mule-app.properties` (or whichever
properties file you used for `slack.webhook.path`) and add a new line:

```properties
slack.warehouse.webhook.path=/services/T01XXXXXXXX/B09YYYYYYYY/zzzzzzzzzzzzzzzzzzzzzzzz
```

`slack.webhook.host` (`hooks.slack.com`) is reused — you don't need a new one.

### 4. Add the new flow to `integration-flows.xml`

Open `src/main/mule/integration-flows.xml` in Anypoint Studio. Paste the contents of
`mulesoft/inventory-check-flow-snippet.xml` from this repo at the bottom of the file,
**right before the closing `</mule>` tag** (i.e. after the `stripe-webhook-flow` definition).

The snippet uses the existing `Salesforce_Config1` and `Slack_HTTP_Config` —
no new connector configuration needed.

### 5. Restart the Mule app

In Anypoint Studio, right-click `technostore-integration` → **Run As → Mule Application**
(or **Restart** if it's already running).

You should see this in the console:

```
Channel Subscription. Successfully subscribed.
  topic=/event/Inventory_Check_Requested__e
```

## Test

1. Open an Order in Salesforce.
2. Click **Request Inventory Check** in the action bar.
3. The Salesforce flow shows a confirmation screen — click **Finish**.
4. Within 1–2 seconds, a Block Kit message appears in `#warehouse` showing:
   - Order number, account, total amount, line count
   - Comma-separated list of products with quantities
   - A **link to the Salesforce Order page**
5. Click that link in Slack → Salesforce opens the Order page.
6. On the Order page, click **Mark In Stock** (or **Mark Out of Stock**) in the action bar.
7. The Order's `Inventory_Status__c` updates instantly, and `Inventory_Confirmed_By__c` +
   `Inventory_Confirmed_At__c` are stamped automatically.

## Troubleshooting

**Slack message never arrives** — Mule console should log
`Channel Subscription. Successfully subscribed`. If not, the Salesforce platform event
permission might be missing for the integration user. Confirm the user can publish
`Inventory_Check_Requested__e` in Salesforce.

**Mule logs `Inventory Check Requested event received` but no Slack message** — the
webhook path is wrong. Test it directly with `curl`:

```bash
curl -X POST "https://${slack_hooks_host}/services/<workspace>/<hook>/<token>" \
  -H 'Content-Type: application/json' \
  -d '{"text":"webhook test"}'
```

**Slack message arrives in the wrong channel** — incoming webhooks are bound to one
specific channel at creation time. Re-create the webhook against `#warehouse` and update
the property.

**Order page doesn't show "Mark In Stock" buttons** — the Order layout was deployed but
your Lightning page might use a different layout assignment. Setup → Object Manager →
Order → Page Layout Assignments → confirm "Order Layout" is the active one for the
running profile, or add the actions to whichever layout you use.
