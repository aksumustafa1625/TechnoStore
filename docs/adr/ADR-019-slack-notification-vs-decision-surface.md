# ADR-019: Slack as Notification Surface, Not Decision Surface

## Status

Accepted — implemented from the first Mule flow that posted to `#warehouse` (memory `inventory_approval_warehouse_flow.md`). All warehouse decisions go through the dedicated Visualforce approval page; Slack notifications link there.

## Context

When a warehouse user needs to confirm or reject an inventory check, there are two viable UI patterns:

1. **Slack as the decision surface** — interactive Block Kit messages with Approve / Reject buttons inline. User clicks a button in Slack, a webhook fires to Salesforce, the approval is processed without the user leaving Slack.
2. **Slack as the notification surface** — Slack message carries the order context and a deep link. User clicks the link, lands on a dedicated Salesforce decision page, makes the choice there.

TechnoStore picked option 2. The warehouse Slack channel gets a Block Kit message with order details when an inventory check is requested; the message contains a single "Open Order in Salesforce" link that takes the user to the `WarehouseInventoryApproval` Visualforce page where they click Mark In Stock / Mark Out of Stock.

A reviewer flagged this as conservative — "modern enterprise integrations use Slack interactivity, not just notifications." That's a fair observation but the trade-off was deliberate.

Three pressures shaped the call:

1. **Auth scope and security**. Slack interactivity requires a Slack App with `interactivity` enabled and a public webhook endpoint that handles signed Slack signature verification. That's an additional auth surface to maintain, an additional secret to rotate, and an additional point of failure for the warehouse approval flow.
2. **Decision context**. The Visualforce page shows the full Order summary, line items, account history, prior approval comments, and a clear two-button decision. Slack Block Kit is fast but cramped — fitting 5 line items, a discount summary, and approver comments into a Slack card requires aggressive truncation.
3. **Audit trail consistency**. The decision goes through `Approval.process()` either way. But routing through the Visualforce page means the controller can validate input, show real-time confirmation, and the audit trail (`ProcessInstanceStep`) is created in the same transaction the user clicks. Slack-side interactivity adds a webhook round-trip that could fail silently if the Slack-side signature verification rejects (rare but possible) — user clicks and sees nothing happen.

## Decision

Slack is the **inbox** for warehouse-facing notifications. The decision page is the dedicated Visualforce surface (`WarehouseInventoryApproval`) with a deep-link from the Slack message.

Concrete flow:

1. Sales rep clicks "Request Inventory Check" on Order.
2. `InventoryCheckService` publishes `Inventory_Check_Requested__e` platform event with order context.
3. Mule listener (`inventory-check-flow`) catches the event, transforms to Slack Block Kit, posts to `#warehouse` channel via incoming webhook.
4. Block Kit card shows: account name, order number, discount, total, line items (top 3 with "+N more"), and a single primary button "Open Order in Salesforce" → deep-link to `/apex/WarehouseInventoryApproval?orderId={Order_Id__c}`.
5. Warehouse user clicks → lands on the VF page (authenticated as themselves via SSO or direct login) → sees full context → clicks Mark In Stock or Mark Out of Stock → controller calls `Approval.process(Approve|Reject)` → audit trail recorded.

The Slack message itself is one-way; it doesn't receive callbacks, has no Approve/Reject buttons, and doesn't need a Slack App with interactivity scope. Only the simpler "Incoming Webhooks" scope is configured (a single webhook URL that posts to the channel).

## Consequences

### Positive

- **Smaller attack surface** — only inbound webhooks from Salesforce to Slack. Slack→Salesforce direction is not authenticated/wired, eliminates that entire class of integration risk.
- **Decision context is rich** — the VF page can show whatever the rep needs (account history, related cases, prior approval comments, even Files attached to the Order). Slack would have to fit all of that into a 6-block card.
- **Audit trail consistency** — `ProcessInstanceStep` is created inside the VF controller's transaction, no async webhook round-trip that could fail. The user sees the result on-page within ~500ms.
- **Slack message is fast to send** — incoming webhook is simpler than Slack interactivity; one HTTP POST and done. Mule flow is small, easy to test.
- **No Slack App management overhead** — TechnoStore doesn't need to maintain a Slack App, request workspace admin to install it, manage permissions, or handle scope changes. The Incoming Webhook is configured once per channel.

### Negative

- **Friction for the warehouse user** — they have to leave Slack and load a Salesforce page to act. Slack-native users find this jarring; the "open Salesforce" click is one extra step.
- **No mobile parity** — Salesforce mobile app exists, but jumping from Slack mobile to Salesforce mobile is a context switch. Slack interactivity would let warehouse users approve from their phone in transit (e.g., during a forklift run). The current flow assumes they're at a desk.
- **Re-enabling Slack as a decision surface requires retrofit** — if the workflow scales and the friction becomes a real cost (e.g., warehouse approval becomes the SLA bottleneck), adding Block Kit interactivity is non-trivial because the existing flow has no Slack App provisioned.

### Future state — when Slack interactivity becomes worth it

Triggers for adding interactivity:

- Warehouse approval latency becomes a documented SLA bottleneck.
- Warehouse users explicitly request mobile-first approval (frequently moving, not at a desk).
- Sales rep complaint volume around "stalled deals waiting on warehouse" exceeds threshold.

Migration path (if needed):

1. Provision a Slack App with `commands`, `interactivity`, and `bot` scopes; install in workspace.
2. Add a public Salesforce Apex REST endpoint `/services/apexrest/slack/interaction` with Slack signature verification.
3. Block Kit message gets two new buttons (Mark In Stock / Mark Out of Stock) alongside the existing "Open Order in Salesforce" link.
4. Endpoint receives the interaction, validates signature, calls `Approval.process()`, returns a Slack response that replaces the message with "Approved by @user".
5. VF page remains as the rich-context surface for exception cases (when warehouse user wants to add a comment or see full order detail before deciding).

Effort: ~3-5 days for the Slack App + endpoint + Block Kit redesign, plus security review of the new endpoint.

## Alternatives Considered

1. **Slack interactivity from day one.** Rejected for the auth-surface and audit-trail reasons above. Also defers the security review until the org has more bandwidth.
2. **Email-based approval** (similar to the email approval response pattern for quote discount approvals, ADR-???). Considered but rejected because warehouse users don't live in email — they live in Slack and the WMS console. Email would be slower than the current Slack→VF flow.
3. **Teams instead of Slack.** Same architectural pattern would work; vendor-substitutable. TechnoStore picked Slack because the demo customer base (Mittelstand DACH) splits about evenly between Slack and Teams; demoing Slack gives broader applicability.
4. **WMS-native approval (e.g., SAP MM stock confirmation transaction).** This is the production target once SAP is wired (see ADR-015 row for Inventory). Until then, the Slack→VF page is the bridge.

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — the inbound webhook scaffolding that exists today is reusable if we later add Slack interactivity. The `JiraStatusWebhook` is a parallel example of an interactive surface; Slack interactivity would mirror that pattern.
- ADR-011 (Inventory Approval Two Convergent Activation Paths) — this ADR explains why Slack is the notification half of Path 1's decision flow; the VF page is the actual decision half.
- ADR-015 (Production Externalization) — the Notification row of the externalisation table notes "Slack already correctly externalised."
