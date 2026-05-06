/**
 * Auto-fills DocumentRecipient.LegalName ("Signer Name" in the CLM Send for Signature UI) from
 * RecipientName when the Recipient Type is "Signer".
 *
 * Why: the runtime_industries_clm__contractSignatureView LWC disables the Signer Name input
 * when Recipient Type = Signer (it expects auto-population from the linked Contact), but the
 * auto-population doesn't always fire — leaving LegalName blank and producing "We couldn't
 * create an envelope because no signers were specified" at send time. Filling LegalName at the
 * trigger level is invisible to the user and makes the native Send for Signature flow work
 * end-to-end without UI gymnastics.
 *
 * Extends Kevin O'Hara TriggerHandler framework (consistent with the rest of this org).
 */
public with sharing class DocumentRecipientTriggerHandler extends TriggerHandler {

    @TestVisible
    private List<DocumentRecipient> records {
        get { return (List<DocumentRecipient>) Trigger.new; }
    }

    protected override void beforeInsert() {
        autoFillSignerName(records);
    }

    protected override void beforeUpdate() {
        autoFillSignerName(records);
    }

    private static void autoFillSignerName(List<DocumentRecipient> recs) {
        if (recs == null || recs.isEmpty()) return;
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
