# ADR-012: Order-First Activation (Pattern 1 — Transactional)

## Status

Accepted — TechnoStore's working pattern since the first Order/Contract flows were built; documented retroactively 2026-05-18 after an external reviewer suggested a sequence flip.

## Context

TechnoStore is a B2B electronics distributor selling **one-time hardware** — workstations, monitors, mechanical keyboards, color-calibrated webcams, ergonomic mice. Each Order is a discrete commercial transaction; there are no subscription products, no multi-year frameworks, no recurring revenue. Quotes flow into Orders, Orders activate, Assets get minted, Contracts run **in parallel** as terms-of-sale agreements (MSA, warranty, payment terms) rather than fulfillment gates.

An architecture reviewer raised the question: should the sequence be flipped so Contract signature happens **before** Order activation, so an unsigned customer never commits inventory or has Assets created in their name? The reviewer's argument: in SaaS / subscription / multi-year enterprise deals, Contract-first is the standard. Salesforce's own sales process runs Contract-first. SAP S/4HANA enterprise sales orders do too.

The decision is whether to flip TechnoStore's flow or formally document the existing Order-first design.

Industry pattern survey (the data behind the call):

| Pattern A — Order-First (current TechnoStore) | Pattern B — Contract-First |
|---|---|
| Lenovo SMB & Mid-Market direct sales | Salesforce SaaS subscriptions |
| Dell Direct, ProSupport hardware refresh | AWS / Microsoft 365 enterprise agreements |
| Cisco Smart Net Distribution channel | Cisco enterprise direct (negotiated multi-year) |
| Apple Business Manager device purchases | Siemens project-based engineering deals |
| Amazon Business B2B catalog orders | SAP S/4HANA negotiated framework agreements |
| HP ProBook channel for resellers | Boeing / Airbus heavy-equipment contracts |

The distinguishing factor is not the size of the company — it is the **shape of the deal**. Discrete one-shot transactions cluster on Pattern A; recurring or multi-year commitments cluster on Pattern B. TechnoStore's profile (one-time hardware, discrete transactions, ASC 606 / IFRS 15 revenue recognised at delivery, no subscriptions) fits Pattern A unambiguously.

A related concern raised: German BGB §280 stock-out liability. If a customer signs a contract with a stated delivery date and the goods aren't available, the seller is on the hook for damages. The reviewer argued Contract-first protects against this. The actual protection is **upstream**: the Inventory Check / ATP Gate ([WarehouseInventoryApprovalController], approval process [Order.Inventory_Approval]) runs before Order activation and blocks the activation when stock is unavailable. Contract signature is not the gate; stock confirmation is. Contract-first would still need an ATP gate to be safe — it doesn't add risk protection over the existing design.

## Decision

Keep Pattern 1. `Order.Status = 'Activated'` is the trigger that runs `OrderTriggerHandler.afterUpdate → createAssetsForActivatedOrders`, minting one Asset per OrderItem. Contract sits in parallel and does not gate Order activation, Asset creation, billing, or fulfillment.

Concretely:

- **Quote → Order conversion**: standard RLM action; produces `Order.Status = 'Draft'`.
- **Request Inventory Check**: VF page approval cycle (`Inventory_Approval` process) confirms stock. Approval path then sets `Order.Status = 'Activated'` (Path 1 — direct via workflow field update) OR if rejected, opens a JIRA ticket which on Done transition triggers `JiraStatusWebhook` and the trigger handler sets `Order.Status = 'Activated'` (Path 2 — convergent).
- **Order activation**: `OrderTriggerHandler.afterUpdate` fires, backfills `BillToContactId` + address fields from the Account, then runs `createAssetsForActivatedOrders` with an idempotency dedup key (Account+Product+OrderNumber). Assets get `Status = 'Purchased'`, `PurchaseDate = Order.EffectiveDate`.
- **Contract** runs as a parallel agreement: `Create_Contract_From_Quote_Custom` can be launched any time after Quote approval, including before or after Order activation. PDF generation, Submit-for-Approval, DocuSign sending, signature, and Activate-Contract all execute on the Contract side without touching Order state. Contract Activated does **not** create Assets (that already happened at Order activation) — the `Activate_Contract_Custom` flow's Source Order path is a no-op when Order is already Activated.
- **Billing Schedules** fire on `Contract.Status = 'Signed'` (record-triggered `Contract_Signed_To_Billing_Schedule` flow) — this is the only point where the Contract side hands work to Order-side records, and it operates on already-activated Orders.

## Consequences

### Positive

- Sales rep finishes the deal at Order activation; Contract paperwork can land hours or days later without holding up fulfillment.
- Revenue recognition aligns with ASC 606 / IFRS 15 control-transfer: ownership transfers at delivery (the Order-side trigger), not at legal signature. The Asset record is the audit anchor for this.
- The ATP Gate (inventory approval before Order activation) is the actual stock-out protection — BGB §280 risk is mitigated upstream of any Contract-signing concern.
- Convergent activation paths (VF approve OR JIRA Done) both land at `Order.Status = 'Activated'`. Sales rep never has to manually flip status.
- Matches the industry default for B2B hardware distribution (Lenovo, Dell, Cisco distribution, Apple Business, Amazon Business). Recruiter recognition is immediate.

### Negative

- A signed Contract is not required before Assets exist on the customer's record. If a customer later disputes the sale before signing, the Asset has to be retroactively voided (a future `Asset.Status = 'Cancelled'` workflow could clean this up; not built today).
- Contract Activated is a separate manual click — sales rep has to remember to do it. Mitigated by the `Activate_Contract_Custom` flow which makes the step a single button rather than a multi-step navigation.
- Reporters or auditors comparing TechnoStore's flow against the Salesforce SaaS sales pattern (Contract-first) will see a difference and might flag it. The recruiter-facing answer is: "different deal shape, different pattern; here is the industry comparison."

### Future state (when subscription products launch)

The day TechnoStore adds a subscription line (software licenses, monthly support plans, SaaS) the right call is **per-product-family pattern routing**:

- Hardware products keep Pattern 1 (current).
- Subscription products switch to Pattern 2 (Contract-first), with Asset creation deferred to `Contract.Status = 'Activated'` and the Order acting as a billing instrument rather than an ownership transfer.

This split is precedent in production at Microsoft (Office 365 vs. Surface), HP (Enterprise Services vs. PCs), Dell (Apex subscription vs. PowerEdge servers). It does not require this ADR to be superseded — both patterns coexist, routed by `Product2.ProductType__c` or equivalent.

## Alternatives Considered

1. **Flip to Pattern 2 (Contract-first)** — rejected for the reasons above; misaligned with the deal shape and would push lead time 3–7 days for no risk reduction.
2. **Hybrid soft-reserve at Draft + hard activate at Contract sign** — over-engineered for one-time hardware. Adds Order state machine complexity (Draft → Reserved → Activated) without business benefit, and the ATP Gate already covers the soft-reserve role.
3. **Quote-level reservation** — reserve stock at Quote approval rather than Order activation. Cleaner for the customer (no "stock just sold out" surprises) but blocks inventory for unconverted Quotes; production data shows Quote-to-Order conversion is around 30–50% so this pattern would lock 50–70% of reserved stock against deals that never close. Punted to roadmap if conversion rates drop.

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — the mechanism behind the JIRA-Done convergent activation path.
- ADR-005 (Kevin O'Hara TriggerHandler adoption) — the framework that `OrderTriggerHandler` extends.
- ADR-013 (Webhook idempotency) — protects the convergent activation path from at-least-once delivery duplicates.
- Future ADR-???: Subscription product family — Pattern 2 routing rule when subscriptions launch.
