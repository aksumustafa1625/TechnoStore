# ADR-020: Visualforce for Warehouse Approval Page (Demo) — LWC for Production

## Status

Accepted — interim. The `WarehouseInventoryApproval` Visualforce page has been the warehouse decision surface since the inventory approval flow was first built. Production-ready version is a Lightning Web Component (LWC) — migration plan documented in this ADR.

## Context

TechnoStore's warehouse approval page is the dedicated UI that warehouse users land on (via the Slack deep-link, per ADR-019) to mark inventory In Stock or Out of Stock for an Order. It shows order context (account, line items, total) and presents two clear action buttons.

Two implementation options:

1. **Visualforce** (legacy but stable) — Apex controller + VF markup. Renders in the Lightning Experience inside an iframe (the "VF in Lightning" wrapping). Renders standalone if accessed via `/apex/PageName?orderId=...`.
2. **Lightning Web Component (LWC)** — modern Salesforce front-end framework. Renders natively in Lightning, supports Locker Service, mobile-friendly, can be embedded in any Lightning page or app.

The page was built with Visualforce. The reviewer (correctly) flagged that "modern enterprise projects would build this as LWC." Two specific reasons the Visualforce choice was made:

1. **Standalone-page rendering**: VF supports `/apex/WarehouseInventoryApproval?orderId={Id}` as a direct URL the Slack message links to, with no Lightning wrapping. LWC has historically required Lightning App / Community context to render; standalone LWC pages are doable via Lightning Out or via Lightning App Pages but add scaffolding.
2. **Speed of build**: a VF page with a controller is ~150 lines total. The equivalent LWC + JS controller + meta-XML + (if standalone) Lightning App Page metadata is ~300-400 lines with more files. For the demo's scope this was overhead without commensurate value.

The migration target is LWC because:

- LWC is what Salesforce themselves are investing in (VF is in long-term-support but no new features).
- Production version benefits from LWC's Locker Service (CSP, XSS protection) more visibly than a VF page.
- LWC components are reusable across Lightning pages, Communities, Mobile App, and Experience Cloud sites. The VF page is rendered in one place.
- Modern Salesforce architects expect LWC; defending VF in an interview is a soft signal.

## Decision

- **Demo today**: Visualforce page (`WarehouseInventoryApproval.page` + `WarehouseInventoryApprovalController.cls`).
- **Production target**: LWC component (`warehouseInventoryApproval`) embedded in a Lightning App Page that's deep-linked the same way the VF page is.
- **Migration path documented in this ADR** so when LWC is needed, the work is well-scoped.

The functional contract stays the same: page receives `orderId` query param, displays order summary + line items, presents Mark In Stock / Mark Out of Stock buttons, controller calls `Approval.process(Approve|Reject)`, JIRA ticket fires on Reject via `JiraTicketService.createTicketAsync()`. The Slack deep-link URL changes from `/apex/WarehouseInventoryApproval?orderId=...` to a Lightning App Page URL like `/lightning/page/warehouseApproval?c__orderId=...`.

## Consequences

### Positive

- **Visualforce works today** — page renders, controller acts, the demo flow is solid. No urgency.
- **Migration path is clear** — same controller logic can be exposed as an `@AuraEnabled` method, called from the LWC. The Apex layer doesn't need rewriting.
- **Locker Service / CSP improvement** — LWC version inherits Salesforce platform security automatically. VF page does too in Lightning context, but native LWC has fewer "edge cases" around XSS escape.
- **Mobile parity** — the LWC version renders in Salesforce Mobile App without the iframe gymnastics VF requires.
- **Recruiter signal** — having an ADR that says "we know VF is legacy, here's the migration plan, it's a 4-hour rewrite" is a stronger signal than ignoring the question.

### Negative

- **VF is technically legacy** — Salesforce hasn't added VF features since ~Spring 2020. The recruiter audience knows this.
- **Slack deep-link URL format will change** — the migration requires updating the Mule flow that builds the Slack Block Kit message to point at the LWC URL. Not hard, but it's a coordinated change across SF + Mule.
- **Two test files** — VF and LWC tests are different. Migration means writing the LWC tests fresh (Jest, not Apex test framework).

### Future state — LWC migration (~4-6 hours)

1. Build `warehouseInventoryApproval` LWC:
   - `.html` template with order summary table, line items, two action buttons.
   - `.js` controller calling `@wire` for record fetch and imperative Apex for the approval action.
   - `.css` for branding (TechStore blue header, button styles).
   - `.js-meta.xml` exposing the component to Lightning App Pages and standalone URL contexts.
2. Refactor `WarehouseInventoryApprovalController` methods to `@AuraEnabled` so LWC can call them.
3. Build Lightning App Page in Lightning App Builder, drop the LWC on it, save with name `warehouseApproval`.
4. Update Mule `inventory-check-flow` Block Kit template to use the Lightning App Page URL instead of `/apex/WarehouseInventoryApproval`.
5. Write Jest tests for the LWC; keep the Apex test for the controller methods (now `@AuraEnabled`).
6. Run end-to-end test: Slack → click link → LWC renders → Mark In Stock → audit trail confirmed.
7. Once validated, retire the VF page (delete the metadata; leave the controller class since it's also used by the audit Task path).

Total: 4-6 hours including testing, no business-process change.

## Alternatives Considered

1. **LWC from day one.** Considered. Costs the demo a few extra hours of scaffolding for a benefit (modern UI framework) that the demo recording doesn't visibly show — the Slack→click→approval flow looks identical to the user.
2. **Aura component.** Rejected — Aura is also legacy; LWC is the forward path.
3. **Native Lightning Approval Page (no custom UI).** The Salesforce standard approval page exists but doesn't support customisation. It shows all the Order fields, not just the ones the warehouse user needs, and is cluttered. Custom UI is justified.
4. **Experience Cloud Community page.** Overkill — the warehouse user is an internal Salesforce user, not an external community member. Community licensing adds complexity and cost.

## Related Decisions

- ADR-011 (Inventory Approval Two Convergent Activation Paths) — Path 1 lands on this VF page; the LWC migration is a UI swap that doesn't change the activation logic.
- ADR-019 (Slack Notification vs Decision Surface) — the Slack deep-link target changes when this migrates from VF to LWC.
- ADR-015 (Production Externalization Strategy) — the UI Framework row of the externalisation table notes "LWC for production" pointing at this ADR.
