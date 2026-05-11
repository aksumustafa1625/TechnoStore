# Postman Collection

This folder contains a **Postman collection + environment** for exercising every external API that TechnoStore integrates with. Use it to:

- Reproduce the end-to-end integration flow without running the Salesforce org
- Test API contracts before wiring them into Apex services or Mule flows
- Onboard new contributors to the integration surface in 30 minutes
- Debug a production issue by replaying the exact HTTP call that Apex / Mule would make

## Files

| File | Purpose |
|------|---------|
| [`TechnoStore.postman_collection.json`](TechnoStore.postman_collection.json) | All HTTP requests organized by external system (JIRA / Notion / DocuSign / Stripe / Sendcloud / Slack / SF Webhooks) |
| [`TechnoStore.postman_environment.json`](TechnoStore.postman_environment.json) | Placeholder environment variables (credentials, base URLs). **Edit locally — never commit your real tokens.** |

## Import

### Postman Desktop app

1. **File → Import** → drag both JSON files in OR click **Choose Files** and select them
2. The collection appears under **Collections** in the left sidebar
3. The environment appears under **Environments**
4. Select **TechnoStore Local** as the active environment (top-right dropdown)

### Postman web (browser)

Same flow — `Import` button on the Workspaces page accepts the same two JSON files.

### CLI (Newman) for headless testing

```bash
npm install -g newman
newman run postman/TechnoStore.postman_collection.json \
  --environment postman/TechnoStore.postman_environment.json
```

## Environment setup — populate the placeholders

The committed `TechnoStore.postman_environment.json` contains **placeholders only**. Replace each `REPLACE_WITH_YOUR_*` value with your real credential in **Postman → Environments → TechnoStore Local → Edit**. Do **not** commit your edits back to git.

| Variable | Where to obtain |
|----------|-----------------|
| `SF_INSTANCE_URL` | `sf org display` → "Instance URL" field |
| `SF_ACCESS_TOKEN` | `sf org display --verbose` → "Access Token" field (refresh as needed) |
| `JIRA_BASE_URL` | Your Atlassian Cloud URL: `https://<your-domain>.atlassian.net` |
| `JIRA_AUTH_TOKEN` | Base64 of `<your-email>:<api-token>`. Generate API token at https://id.atlassian.com/manage-profile/security/api-tokens |
| `JIRA_PROJECT_KEY` | Your JIRA project key (e.g., `TS` for TechnoStore) |
| `JIRA_BOARD_ID` | From the JIRA Board URL: `/jira/software/c/projects/TS/boards/<id>` |
| `NOTION_TOKEN` | Internal Integration secret from https://www.notion.so/profile/integrations |
| `NOTION_PARENT_PAGE_ID` | UUID of the parent Notion page (from URL: `notion.so/Page-Title-<32-char-hex>`) |
| `DOCUSIGN_BASE_URL` | `https://demo.docusign.net` (sandbox) or `https://account-d.docusign.com` (prod) |
| `DOCUSIGN_ACCOUNT_ID` | From DocuSign Admin → API and Keys → Account ID (UUID) |
| `DOCUSIGN_ACCESS_TOKEN` | OAuth access token. Generate via DocuSign OAuth flow or use Authorization → OAuth 2.0 in Postman to populate. |
| `STRIPE_SECRET_KEY` | `sk_test_*` from Stripe Dashboard → Developers → API keys (use Test mode) |
| `STRIPE_WEBHOOK_SECRET` | `whsec_*` from Stripe Dashboard → Developers → Webhooks → Signing secret |
| `SENDCLOUD_PUBLIC_KEY` | Sendcloud Panel → Settings → Integrations → API |
| `SENDCLOUD_SECRET_KEY` | Same screen (paired with public key) |
| `SENDCLOUD_INTEGRATION_ID` | Sendcloud account-level identifier (`577997` for the TechnoStore demo account) |
| `SLACK_PAYMENTS_WEBHOOK_URL` | Slack App → Incoming Webhooks → URL for `#payments-team` channel |
| `SLACK_WAREHOUSE_WEBHOOK_URL` | Slack App → Incoming Webhooks → URL for `#warehouse` channel |
| `MULE_BASE_URL` | `https://technostore-mule.cloudhub.io` (or `http://localhost:8081` for local Mule Standalone) |

## What's in the collection

Organized into folders by external system:

```
TechnoStore Integration APIs
├── 1. JIRA Cloud (outbound)
│   ├── Create issue
│   ├── Create sprint
│   ├── Add issues to sprint
│   └── Set story points
│
├── 2. Notion (outbound)
│   ├── Create page (with title only)
│   ├── Append children (toggle blocks)
│   └── Retrieve page
│
├── 3. DocuSign (outbound)
│   ├── Create envelope (Send for Signature)
│   └── Get envelope status
│
├── 4. DocuSign Webhook Simulator (inbound -> SF Site)
│   └── Simulate envelopeStatus=Completed event
│
├── 5. Stripe (via Mule)
│   ├── Create PaymentIntent (POST /stripe/intent)
│   └── Simulate Stripe webhook (POST /stripe/webhook)
│
├── 6. Sendcloud v3 Orders (via Mule)
│   └── Create order (POST /sendcloud/order)
│
├── 7. Slack Notifications (outbound)
│   ├── Post to #payments-team
│   └── Post to #warehouse
│
└── 8. Salesforce REST API (sanity checks)
    ├── Query Accounts (SOQL)
    ├── Get current user
    └── Create Account (for testing)
```

Each request has:

- **Pre-request script** that fills in dynamic values (timestamps, UUIDs) where needed
- **Headers** with the correct authentication for the target system
- **Body** showing a realistic example payload
- **Tests** that assert response shape + persist returned IDs to environment variables (so subsequent requests can chain)

## Chained workflow examples

The collection supports running requests in sequence to reproduce real integration flows:

### "Create JIRA ticket on Order activation" flow

1. **JIRA Cloud → Create issue** — captures `issueKey` to `{{LAST_JIRA_ISSUE_KEY}}` env var
2. **JIRA Cloud → Add issues to sprint** — uses `{{LAST_JIRA_ISSUE_KEY}}` from step 1

### "Notion portfolio publish" flow

1. **Notion → Create page** — captures returned page ID to `{{LAST_NOTION_PAGE_ID}}`
2. **Notion → Append children** — uses `{{LAST_NOTION_PAGE_ID}}` to add toggle blocks
3. **Notion → Retrieve page** — verifies the structure

### "Stripe payment loop" flow

1. **Stripe → Create PaymentIntent (via Mule)** — captures `paymentIntentId`
2. **Stripe → Simulate webhook** — sends a fake `payment_intent.succeeded` event for the captured `paymentIntentId` (useful for testing the Mule webhook handler without making a real card payment)

## Conventions

### Authentication

- **JIRA** — Basic Auth with `Authorization: Basic {{JIRA_AUTH_TOKEN}}` (base64 of `email:token`)
- **Notion** — Bearer token with `Authorization: Bearer {{NOTION_TOKEN}}`
- **DocuSign** — Bearer token with `Authorization: Bearer {{DOCUSIGN_ACCESS_TOKEN}}` (Postman OAuth 2.0 can auto-refresh)
- **Stripe** — Basic Auth with username = secret key, empty password (Stripe's quirk)
- **Sendcloud** — Basic Auth with `{{SENDCLOUD_PUBLIC_KEY}}:{{SENDCLOUD_SECRET_KEY}}`
- **Slack** — No header auth; the webhook URL itself is the credential (POST to `{{SLACK_PAYMENTS_WEBHOOK_URL}}` etc.)
- **Salesforce** — Bearer token with `Authorization: Bearer {{SF_ACCESS_TOKEN}}`

### Variable scoping

- **Environment variables** — credentials, base URLs, account IDs (per-org, can change between dev/sandbox/prod)
- **Collection variables** — none; everything is environment-scoped
- **Local variables** (set by Tests scripts) — `LAST_JIRA_ISSUE_KEY`, `LAST_NOTION_PAGE_ID`, etc. — captured outputs for chaining

### Security note

**Never commit your populated environment file** to git. The committed version has only placeholder values. Add a real environment as a second JSON file locally (e.g., `TechnoStore.postman_environment.local.json`) and ensure it's listed in `.gitignore`. The `.gitignore` already excludes `**/*.local.json` patterns.

## Related documentation

- [OpenAPI specifications](../openapi/README.md) — formal API contracts for the endpoints TechnoStore exposes
- [Architecture diagrams](../docs/architecture/) — system-level context
- [ADR-001](../docs/adr/ADR-001-mule-vs-apex-decision-matrix.md) — why each integration is in Mule vs Apex (and thus where each request in this collection targets)
- [CONTRIBUTING.md](../CONTRIBUTING.md) — secrets management conventions
