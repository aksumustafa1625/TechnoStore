# ADR-007: Org-Wide Email Address for DACH B2B Deliverability

## Status

**Accepted**

## Date

2026-05-02

## Author

Mustafa Aksu

## Context

TechnoStore sends **five customer-facing emails per Order lifecycle**:

1. **Orange INVOICE PDF + Pay Now button** â€” fires on Order activation (pre-payment)
2. **Green RECEIPT PDF** â€” fires on Stripe `payment_intent.succeeded` webhook (post-payment)
3. **Shipping notification with tracking link** â€” fires after Sendcloud parcel + DHL pickup (Physical fulfillment path)
4. **License key welcome email** â€” fires after license UUID generation (Digital fulfillment path)
5. **DocuSign signing request** â€” fires when sales rep clicks Send For Signature

Each of these emails must **land in the customer's primary inbox**, not the spam folder. The customer base is **DACH-market enterprise IT buyers** running corporate B2B mail tenants: Microsoft 365, Google Workspace, Outlook on-prem, T-Online business. These tenants apply aggressive heuristic spam filtering, with several rules that consumer-Gmail senders consistently trip:

- **Sender domain mismatch** â€” if the message claims to be from "TechnoStore" in the body but the From header is `admin@technostore.example`, modern spam filters score this as suspicious (the body content doesn't match the sender identity).
- **Consumer mail domain** â€” `@gmail.com`, `@yahoo.com`, `@hotmail.com` are statistically much more likely to be phishing in B2B inboxes. Score elevated.
- **No SPF/DKIM/DMARC alignment** â€” when From is `admin@technostore.example`, the receiving server's SPF check passes (it's actually from Gmail), but the recipient's heuristics still penalize the consumer-mail-to-corporate-B2B mismatch.

Salesforce's default `Messaging.SingleEmailMessage` behavior uses **the running user's email address as the From header** (`UserInfo.getUserId()` â†’ User.Email). For the TechnoStore Dev Edition, that's `admin@technostore.example` â€” the OAuth runtime user. Every customer email lands From `admin@technostore.example`, indistinguishable from a phishing attempt to a corporate spam filter.

Beyond deliverability, there is a **branding consistency issue**: a customer who pays â‚¬1,499 for a Workstation Pro should not see the confirmation email arrive From a personal Gmail. The presentation breaks credibility.

## Decision

Configure a **Salesforce Org-Wide Email Address** (`OrgWideEmailAddress`) and apply it to **all five customer-facing email invocables**:

- Display Name: `TechnoStore`
- Email Address: `noreply@technostore.example` (placeholder for the demo; production will use a real owned domain)
- Allow All Profiles to Use this From Address: `true`

In each email invocable Apex class (`AttachAndEmailInvoicePreview`, `EmailWithBrandedPdf`, `ShippingNotificationEmail`, `LicenseWelcomeEmail`, and the DocuSign send email block), query the Org-Wide Address Id once and set it on every `SingleEmailMessage`:

```apex
Id orgWideId = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'TechnoStore' LIMIT 1].Id;
// ... per email:
email.setOrgWideEmailAddressId(orgWideId);
email.setReplyTo('support@technostore.example');  // monitored inbox
```

The Reply-To header is set to a **separate monitored support address** so customer replies route to a real inbox (rather than no-reply where they would be lost).

Salesforce Email Deliverability setting (Setup â†’ Email Administration â†’ Deliverability) is configured to **Access Level = All Email** so production-mode outbound is enabled (the default `System Email Only` is sandbox-safe but blocks customer emails).

For **production deployment**, the placeholder domain (`technostore.example`) is documented as a Q3 2026 work item: register a real domain (`technostore.de`), configure DNS with **SPF** (`v=spf1 include:_spf.salesforce.com -all`), **DKIM** (Salesforce-provided selector under Setup â†’ DKIM Keys), and **DMARC** (`v=DMARC1; p=quarantine`). Without those DNS records, even Org-Wide Address won't survive the strictest B2B filters.

## Consequences

### Positive

- **Test emails to corporate B2B test inboxes land in primary inbox** â€” verified against a Microsoft 365 test tenant + Google Workspace test tenant; both placed the INVOICE email in primary, not spam.
- **Customer inbox displays `From: TechnoStore <noreply@technostore.example>`** â€” corporate sender identity, professional presentation, matches the branded PDF inside the email.
- **Replies route to monitored inbox** â€” customer "I have a question about my invoice" lands at `support@technostore.example` (a real address), not at the no-reply sender.
- **Consistent across all 5 email surfaces** â€” sales reps cannot accidentally send an INVOICE from their personal email because the invocable hardcodes the Org-Wide Address Id.
- **Audit trail** â€” `EmailMessage` records show the Org-Wide Address Id, providing traceability for "who sent which email when" without leaking individual rep emails.

### Negative / Trade-offs

- **Verification round-trip required** â€” Salesforce sends a confirmation email to the configured address; an admin must click the verification link. Demo placeholder `noreply@technostore.example` requires either: a working catch-all on the example.com domain, or temporarily using a real inbox you control for the verification step.
- **Production needs real domain + DNS** â€” `technostore.example` is a demo placeholder. Production launch requires owned domain + SPF + DKIM + DMARC. Documented as future work but not a blocker for the demo recording.
- **Cannot send from individual reps** â€” once an email invocable hardcodes the Org-Wide Address, sales reps cannot override per-message even if they have a legitimate reason to send from their identity. Mitigated by: customer-facing emails should always be branded TechnoStore; rep-to-customer 1:1 emails happen outside the Order email workflow (via Salesforce Email Templates with the rep's identity).
- **One central credential is a small concentration of risk** â€” if the Org-Wide Address mailbox is compromised, every TechnoStore-branded email could be hijacked. Mitigated by: standard MX + SPF + DKIM + DMARC + mailbox-level 2FA (production hardening item).

## Alternatives Considered

### Alternative A â€” Use the running user's email (Salesforce default)

Rejected because:
- Deliverability into corporate B2B inboxes is poor (spam-filter trip).
- Branding is inconsistent (customer sees `admin@technostore.example` for a TechnoStore invoice).
- Replies route to the personal Gmail of whoever happened to activate the Order.

### Alternative B â€” Send via SendGrid / Mailgun / SES external mail service

Considered. Rejected because:
- Adds an integration dependency for a problem Salesforce already solves (Org-Wide Email Addresses).
- Requires Apex callouts per email (Salesforce 100-callout governor; viable but unnecessary complexity).
- Loses Salesforce-native audit trail (`EmailMessage` records, Email Tracking).
- DACH compliance: data-residency questions arise when customer emails route through US-hosted email APIs.

### Alternative C â€” Per-feature Org-Wide Addresses (one for INVOICE, one for RECEIPT, etc.)

Considered for marketing teams that want different sender personas. Rejected because:
- Five different sender names dilutes the TechnoStore brand identity.
- Each Org-Wide Address requires its own DNS + verification â€” five times the production hardening cost.
- B2B buyers expect consistency: "if I order from TechnoStore, I should hear back from TechnoStore, not from 'TechnoStore Billing' for one email and 'TechnoStore Shipping' for another."

### Alternative D â€” Use Mule SMTP connector to send via owned mail server

Considered for full integration with the rest of the Mule orchestration layer. Rejected because:
- Salesforce-native Email Templates + branded PDFs + `Messaging.SingleEmailMessage` integration with `Order` / `Contract` records is the cleanest workflow.
- Mule SMTP would require duplicating the `EmailMessage` audit trail in Salesforce (via SF Connector update) â€” net more code, not less.

## Future work

Documented as Q3 2026 production hardening tasks (see `roadmap` in `README.md`):

1. Register `technostore.de` domain (replaces placeholder `technostore.example`).
2. Configure DNS records:
   - `SPF`: `v=spf1 include:_spf.salesforce.com -all`
   - `DKIM`: enable in Setup â†’ DKIM Keys, publish the public-key TXT record at the Salesforce-provided selector
   - `DMARC`: `v=DMARC1; p=quarantine; rua=mailto:dmarc@technostore.de; pct=100`
3. Re-verify the Org-Wide Address against the new domain.
4. Test deliverability against the corporate B2B test inboxes again.

DACH-localized email content (German subject lines + body for AT/DE accounts, German + French for CH accounts) is a separate localization work item.

## References

- **Memory**: `technostore_branded_pdf_email_system.md`
- **Notion portfolio entries**: 32 (Branded Invoice + Receipt PDF System), 48 (Email System â€” Org-Wide Address + Spam Avoidance)
- **Code**: `force-app-actions/main/default/classes/AttachAndEmailInvoicePreview.cls`, `EmailWithBrandedPdf.cls`
- **Setup**: Setup â†’ Email Administration â†’ Organization-Wide Addresses
- **Related ADRs**: ADR-008 (Flying Saucer VF PDF â€” the PDFs attached to these emails)
- **Salesforce docs**: [Organization-Wide Email Addresses](https://help.salesforce.com/s/articleView?id=sf.emailadmin_setup_orgwide.htm)
