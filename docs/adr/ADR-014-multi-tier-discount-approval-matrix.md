# ADR-014: Multi-Tier Discount Approval Matrix

## Status

Accepted — implemented 2026-05-17; the prior single-step `TechStore_Quote_Approval` process was retired the same day and is preserved as Obsolete for audit history.

## Context

The original Quote approval process was a flat single-step: any Quote with Discount > 20% routed to one approver (the Sales Manager). The approver clicked Approve and the Quote moved to Approved. This worked for a demo of a small B2B SaaS company but failed three real-world tests:

1. **Deal-desk governance**: B2B enterprise companies don't let one Sales Manager rubber-stamp a 70% discount. Higher discounts cross financial-impact thresholds and need Finance and VP-Sales sign-off. The single-step model invites compliance findings.
2. **Recruiter interview signal**: every senior Salesforce interviewer asks "how does your approval matrix scale beyond one step?" The single-step model gave a thin answer.
3. **Email Approval Response composition**: the branded approval email template `Quote_Approval_Request` (ADR-???) shows tier-aware messaging ("Tier 2 — Finance approval"). Without an actual multi-step backing process, the email's claim was empty.

Three escalation tiers are the industry default for B2B Quote-to-Cash deal desks: a manager-level approval (small deals), a finance-cross-check (mid deals), and a VP/CFO sign-off (large deals or strategic accounts). The thresholds (20%, 30%, 50% discount) match the breakpoints used by Cisco's Smart Solutions deal desk, HP's PartnerOne approval matrix, and Dell's commercial sales authority. Anything below 20% is auto-approved — sales rep self-service.

A constraint specific to Salesforce: **active approval processes are step-locked**. Once a process is Active in production, you cannot add or remove steps via metadata — the system refuses the deploy with `Active approval process can't be modified`. The fix is to clone the process to a new API name and deactivate the old one. This forced the rename to `TechStore_Quote_Approval_Multitier` rather than editing the original in place.

## Decision

Three-tier approval process `TechStore_Quote_Approval_Multitier` on Quote, entry criteria `Discount > 0.20`, three sequential steps. Each step has its own approver and exits via `ifCriteriaNotMet=ApproveRecord` so a deal that doesn't meet a higher tier's threshold auto-passes that step rather than getting stuck.

Tier breakdown:

| Tier | Discount range | Approver role | Approval steps to clear | Email greeting (tier-aware) |
|---|---|---|---|---|
| Auto-approve | 0–20% | (no human) | 0 | (no email sent) |
| Tier 1 | 20–30% | Sales Manager | 1 | "Tier 1 — Manager approval" |
| Tier 2 | 30–50% | Sales Manager → Finance Director | 2 | "Tier 2 — Finance approval" |
| Tier 3 | 50%+ | Sales Manager → Finance Director → VP Sales | 3 | "Tier 3 — VP-level approval" |

Entry criteria on each step:

- Step 1 (Sales Manager): always fires; no entry criteria
- Step 2 (Finance Director): `Quote.Discount > 0.30`, else auto-pass
- Step 3 (VP Sales): `Quote.Discount > 0.50`, else auto-pass (and complete the process)

The Discount field is stored as a fraction (0.51 for 51%) at the database layer, displayed as percentage in the UI. The entry-criteria expressions use fractions accordingly. The `Submit_Quote_For_Approval` flow uses percentage values (20, 30, 50) because Flow auto-converts Percent-type fields for display — both conventions coexist correctly.

A new Quote formula field `Approval_Tier_Label__c` returns the tier name based on Discount (`IF Discount > 0.50 then "Tier 3 - VP Sales Approval" else …`). This field is referenced by the branded email template so each approval email surfaces the relevant tier label inline.

The Submit-for-Approval screen flow (`Submit_Quote_For_Approval`) was also updated with three Flow formula resources:

- `Approval_Tier_Label` → "Tier 1 - Manager approval" / "Tier 2 - Finance approval" / "Tier 3 - VP-level approval"
- `Approval_Path` → "Sales Manager only" / "Sales Manager → Finance Director" / "Sales Manager → Finance Director → VP Sales"
- `Threshold_Reference` → "20%" / "30%" / "50%" (the boundary the current Discount just crossed)

Both the Submit screen and the post-submit "Submitted" confirmation screen merge these formulas so the user sees tier-aware copy. The pre-submit screen reads "This quote has a discount of X%, exceeding the [Threshold_Reference] approval threshold. [Tier_Label]. This quote will route through [Approval_Path]."

The demo currently uses `technostore-admin@example.com` (Mustafa Aksu) as the single approver for all three steps. In production, the three roles would be assigned to three different users via the User.ManagerId hierarchy or a custom `Approval_Role__c` lookup; the metadata structure already supports this swap without process re-cloning.

## Consequences

### Positive

- Discount tier governance is now visible and auditable: the Approval History related list on Quote shows the exact path a deal took, with step labels and approver comments.
- Email Approval Response (ADR-???) composes cleanly: each step generates its own branded notification with the matching tier label.
- Recruiter answer for "how does your approval matrix scale?" becomes concrete: three sequential steps, tier-aware UI copy, formula-driven label, demo-tested at 21% / 31% / 51% with the expected 1/2/3 emails arriving.
- The auto-pass behavior on Step 2 and Step 3 means a low-discount Quote still cleanly goes through the multi-tier process without false escalations.

### Negative

- Demo recording shows the same user (Mustafa Aksu) approving three times for a Tier 3 deal. The visual is repetitive. The narration must explain "in production these would be three distinct users" — without that explanation, the multi-tier value isn't obvious from the screen.
- Three Steps mean three separate Approver notifications, three clicks per Tier 3 deal. Production users will use Email Approval Response (reply with APPROVE) to short-circuit, but new approvers might find the flow heavy until they learn the shortcut.
- A future change to the threshold breakpoints (e.g. lowering Tier 2 to 25%) requires editing entry-criteria on a now-active process. Salesforce will refuse the metadata deploy of the active process. The escape hatch is the same as the original migration: rename to `_Multitier_v2`, deactivate _Multitier, deploy fresh. Plan for one rename per material threshold change.

### Future state

- Replace the static-threshold model with a `Discount_Approval_Threshold__mdt` Custom Metadata Type so the breakpoints are configurable without rebuilding the process. The process entry criteria would read from formula fields that reference the mdt.
- Add a fourth tier for strategic accounts: any Quote on an Account flagged `Strategic_Account__c = true` routes through Step 4 (CFO sign-off) regardless of discount.
- Wire a `Process_Builder` or Flow on Quote that auto-recalls and resubmits the approval when the Discount changes mid-flight (sales rep adjusts mid-negotiation). Currently the rep has to manually recall + resubmit.

## Alternatives Considered

1. **Edit the existing approval process in place** — rejected because Salesforce step-locks active processes. The clone-then-deactivate pattern was the only metadata-deployable path.
2. **Separate approval process per tier** (three independent processes with different entry criteria) — rejected because Quote can only be in one approval process at a time. We'd have to chain them manually via Apex submit-on-approve, which reintroduces the complexity we tried to escape.
3. **Workflow + Email Alert pattern** (no Approval Process; just emails with a manual Status field update) — rejected for audit-trail loss; standard Approval Process gives `ProcessInstanceStep` records out of the box for every Approve/Reject click.
4. **External deal-desk tool** (e.g., DealHub, Conga Approvals) — overkill for the demo and adds a license cost. Native Salesforce approval is sufficient at this scale; the external tool is justified only when the matrix grows past ~10 tiers or needs complex routing logic (territory, product family, contract type).

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — independent; this ADR doesn't touch the guest user flow.
- Future ADR-???: Email Approval Response + branded `Quote_Approval_Request` template — this ADR composes with it; the email template merges the `Approval_Tier_Label__c` formula and references `{!ApprovalRequest.External_URL}` for the click-through.
- Future ADR-???: Production Externalization Strategy — at that point the threshold breakpoints would migrate to `Discount_Approval_Threshold__mdt` per the future-state note above.
