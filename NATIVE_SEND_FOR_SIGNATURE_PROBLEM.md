# Salesforce CLM Industries — Native Send for Signature: Signer Name Field Disabled, Cannot Send Envelope

## TL;DR

The native CLM Industries `runtime_industries_clm__contractSignatureView` LWC's "Add Recipient" dialog **disables the Signer Name input when Recipient Type = Signer** and never auto-populates it. Clicking Send returns:

> **"We couldn't create the envelope because the signer details are empty. Specify valid signer details for the signers and try again."**

We need to either (a) make the field editable / auto-populate, or (b) inject a Signer Name into the recipient via a server-side hook so the validation passes — without modifying the managed LWC, which we can't.

---

## Context

- Org: Salesforce Dev Edition with **Industries CLM** (Contract Lifecycle Management) installed.
- The Contract object has a "Send for Signature" lifecycle button that opens this URL:
  `/lightning/cmp/runtime_industries_clm__contractSignatureView?c__recordId=<ContractId>&c__objectApiName=Contract`
- The page is a managed Lightning Web Component (`runtime_industries_clm__contractSignatureView`). We do NOT have source access — it ships in the managed package.
- The page lets the user attach a PDF, add recipients, write a custom email message, and click **Send** to create a DocuSign envelope.
- DocuSign integration in this org is fully working through a custom "Send Via DocuSign" quick action (envelope creation, email delivery, signed-status webhook) — proven end-to-end. So the underlying DocuSign auth/named credential / vendor account ID are correct.
- The user's goal is to use the **native** Send for Signature page during the demo because its visual flow (PDF picker, recipient cards, message editor, attach panel, notification config) is more impressive than the custom button.

---

## The bug we hit

Steps to reproduce:

1. Open a Contract → click **Send for Signature** → page loads correctly.
2. Click **Add Recipient**. The "Add Recipient" modal opens.
3. **Recipient Information** section — fields filled by typing/selecting:
   - Recipient Name: `Lukas Müller` (a valid Contact lookup; pick from search).
   - Recipient Email: auto-populates as `demo-user@example.com` from the contact (so the contact lookup is wired correctly).
   - Recipient Type: `Signer` (required for email-based remote signing).
   - Recipient Locale: `English (U.S.)`.
4. **Signer Information** section:
   - Signer Role: `Customer Signer` (one of the entries in `ESignatureConfig.ConfigType=SignerRoles.ConfigValue`).
   - **Signer Name: the input is disabled, shows the gray placeholder "Enter signer name…", and accepts no keyboard input. The user cannot type into it.**
5. **Order and Code** section: Routing Order = 1, Access Code = 1234.
6. Click **Save**. The recipient is added to the "Choose Signers" table on the parent page. In that table, the Signer Name column for this row is empty.
7. Write Email Subject + Email Message, attach the PDF, click **Send**.
8. Red toast: **"We couldn't create the envelope because the signer details are empty. Specify valid signer details for the signers and try again."**

### Side observation that confirms the field disable is type-specific

If we change Recipient Type from `Signer` to `Host In Person`, the Signer Name input becomes ACTIVE and accepts text. We typed `Lukas Müller` into it and the row saved with the name visible in the Signer Name column. But that recipient counts as a "host" in DocuSign — not a remote-email signer — so it doesn't satisfy the demo (no email goes to the customer; it's an in-person kiosk flow).

**So the LWC clearly has different field-enabled rules for `Signer` vs `Host In Person`.** For `Signer`, the field is intentionally disabled, presumably because the LWC expects to auto-populate it from the linked Contact's name. The auto-population is what's silently failing.

---

## What the underlying data model looks like

We probed the org's schema with Tooling API:

- The recipient object is **`DocumentRecipient`** (`IsTriggerable = true`).
- Relevant fields:

| API Name | Type | Notes |
|---|---|---|
| `RecipientName` | string | The display name of the contact (e.g. "Lukas Müller"). |
| `Email` | email | Recipient email. |
| `Type` | picklist | `Signer`, `Host In Person`, etc. |
| `LegalName` | string | **This is the field shown as "Signer Name" in the LWC.** |
| `RoutingOrder` | integer | Sign order. |
| `RecipientId` | reference | Lookup back to Contact / User. |
| `DocumentId` | reference | Lookup to the document/envelope. |
| `Status`, `StatusReason`, `LocaleCode`, `DocumentAccessKey`, etc. |  | |

- `LegalName` is the **only** field on any standard object in this org named `LegalName` (verified via `EntityParticle WHERE QualifiedApiName='LegalName'`).
- `ESignatureConfig` has 3 records:
  - `SignerRoles` / `AnchorTabSetting` — value: `Customer Signer,Internal Approver,Witness,CC Recipient`
  - `CalloutNamedCredential` / `CalloutConfigurationSetup` — value: `DocuSign`
  - `eSignVendorAccountId` / `eSignVendorAccount` — value: `47481170`
- No custom validation rule, Apex trigger, or flow exists on `DocumentRecipient` from the customer side (only the one we deployed during this investigation).

Critical observation: **The "Choose Signers" table on the LWC shows recipients the user has added, but no rows are present in the `DocumentRecipient` table during this period.** We queried `SELECT COUNT() FROM DocumentRecipient` and `SELECT COUNT() FROM DocumentEnvelope` after adding 2 recipients via the Add Recipient dialog and got **0** for both. This means the recipients live in the LWC's in-memory state until **Send** succeeds, at which point the LWC creates the envelope + recipient rows + calls DocuSign in a single transaction. **Validation runs against the in-memory state before any DML happens**, which is why our triggers can't intercept.

---

## What we tried

### Attempt 1 — Apex `before insert / before update` trigger on DocumentRecipient

We deployed a thin trigger + handler (Kevin O'Hara framework) that auto-fills `LegalName` from `RecipientName` when `Type = 'Signer'` and `LegalName` is blank:

```apex
trigger DocumentRecipientAutoFillSignerName on DocumentRecipient (before insert, before update) {
    new DocumentRecipientTriggerHandler().run();
}

// handler
public with sharing class DocumentRecipientTriggerHandler extends TriggerHandler {
    @TestVisible private List<DocumentRecipient> records {
        get { return (List<DocumentRecipient>) Trigger.new; }
    }
    protected override void beforeInsert() { autoFillSignerName(records); }
    protected override void beforeUpdate() { autoFillSignerName(records); }
    private static void autoFillSignerName(List<DocumentRecipient> recs) {
        for (DocumentRecipient dr : recs) {
            if (String.isBlank(dr.LegalName)
                && String.isNotBlank(dr.RecipientName)
                && dr.Type != null
                && dr.Type.equalsIgnoreCase('Signer')) {
                dr.LegalName = dr.RecipientName;
            }
        }
    }
}
```

Deploy succeeded. We re-attempted the Send — same error. After the failed Send, we queried `DocumentRecipient` and found **zero rows**. **Conclusion**: the LWC validates in-memory before any DML. The trigger never fires because the insert never happens.

### Attempt 2 — Verify the linked Contact has all expected fields

Maybe the auto-population needs FirstName + LastName + Name to all be populated:

```sql
SELECT Id, FirstName, LastName, Name, Email FROM Contact WHERE Email='demo-user@example.com'
```

Returned `Lukas / Müller / Lukas Müller / demo-user@example.com`. All standard fields present, formula `Name` resolved correctly. Still no auto-population.

### Attempt 3 — Inspect ESignatureConfig for a field-mapping setting

Three records, listed above. None of them looks like a "RecipientFieldDefaults" / "SignerNameFromContactField" mapping. We searched for the string `LegalName` across `EntityParticle` — only one entity has it (`DocumentRecipient`), and there is no apparent CLM config that maps a Contact field to it.

### Attempt 4 — Look for any published API hook or "before-send" flow trigger surface

`runtime_industries_clm` is a managed namespace. No platform event, invocable apex, or autolaunched flow ships on it that would let us pre-process recipients at Send time. The LWC's `send` button calls a server controller method whose name we cannot see (managed code).

### Attempt 5 — Click directly into the "Enter signer name..." input and try to type

The input rejects keystrokes when Recipient Type = Signer (visually grey placeholder, no caret on click). When Recipient Type = Host In Person, the same input becomes editable. So the disable is conditional on the Type value inside the LWC's render logic.

---

## Why a simple workaround doesn't fit the demo

- **Use Host In Person instead**: technically "works" (the form saves and the envelope is sent), but DocuSign treats Host In Person as a kiosk flow, not a remote-email signer. The customer doesn't get the right email experience.
- **Use the existing custom DocuSign quick action**: works end-to-end, but bypasses the visually-rich native page. The user wants the native page for the demo.
- **Modify the LWC**: not possible — it's managed.

---

## What we'd love a consultant to tell us

1. **What auto-population logic does `runtime_industries_clm__contractSignatureView` actually run for `LegalName` when `Type = Signer`?** Specifically, what Contact field (or other source) is it reading? If we know the source, we can ensure the data is shaped correctly.
2. **Is there a `ConfigType` we can add to `ESignatureConfig`** (or another managed config object) that overrides the LegalName source, or marks the Signer Name field as user-editable for Type=Signer?
3. **Is there a documented or undocumented hook** (Apex Invocable, Platform Event, Flow) that the LWC publishes on Save / before Send that we can subscribe to and inject `LegalName` into the in-memory recipient before validation runs?
4. **Is the disable behavior controlled by a feature flag or Permission Set License** (`IndustriesEinsteinFeature`, `ContractsAI`, etc.) that we may not have enabled in this Dev Edition?
5. **Is there a known Salesforce bug/release note** describing this behavior and a recommended workaround? (We searched Trailblazer Community and Known Issues; nothing direct.)
6. **Is there a way to override the LWC's Type picklist values** so that `Signer` follows the same code path as `Host In Person` while still being treated as a remote signer downstream in DocuSign?

## Repo Snapshot

- Org: your-org.develop.my.salesforce.com (Dev Edition)
- DocuSign integration in this org: `force-app/main/default/namedCredentials/DocuSign.namedCredential-meta.xml`, `Contract.DocuSign_Envelope_Id__c` field, `DocuSignConnectWebhook` REST class with `DocuSign_Status_Update__e` Platform Event indirection, `Contract.Send_Via_DocuSign.quickAction-meta.xml` (custom button that DOES work and bypasses the broken native flow).
- Investigation trigger: `force-app/main/default/triggers/DocumentRecipientAutoFillSignerName.trigger` + `force-app-handlers/main/default/classes/DocumentRecipientTriggerHandler.cls` (deployed; never fires because no DML hits `DocumentRecipient` before validation).
- Failure surface: the Add Recipient dialog inside `/lightning/cmp/runtime_industries_clm__contractSignatureView?...&c__objectApiName=Contract&c__recordId=<id>`.
