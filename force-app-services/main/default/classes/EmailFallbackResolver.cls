/**
 * Resolves the recipient address for outbound customer emails.
 *
 * Priority:
 *   1. The Contact's email passed in (preferred — the actual customer)
 *   2. Email_Config__c.Default_Fallback_Email__c (Protected Hierarchy Custom Setting)
 *
 * If both are missing, throws EmailFallbackException — this is intentional in
 * production: a missing Contact email AND a missing fallback signals a real
 * data-quality problem that should not silently send mail to a dev mailbox.
 *
 * In demo/dev orgs: populate the Custom Setting via scripts/setup_email_config.apex
 * (gitignored) so the fallback exists and Invoice flows do not throw.
 *
 * In production orgs: leave Email_Config__c.Default_Fallback_Email__c blank
 * so the throw forces upstream data quality fixes (every customer must have
 * a Contact email).
 *
 * Replaces a previous hardcoded developer-mailbox fallback that was
 * duplicated across AttachAndEmailInvoicePdf, AttachAndEmailInvoicePreview,
 * and EmailWithBrandedPdf.
 */
public with sharing class EmailFallbackResolver {

    /**
     * Returns the email address to use as the recipient.
     * @param contactEmail The Contact's email, or null if not available.
     * @return The resolved recipient address.
     * @throws EmailFallbackException if neither contact email nor fallback is set.
     */
    public static String resolve(String contactEmail) {
        if (String.isNotBlank(contactEmail)) {
            return contactEmail;
        }
        Email_Config__c cfg = Email_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Default_Fallback_Email__c)) {
            throw new EmailFallbackException(
                'No Contact email available AND no Email_Config__c.Default_Fallback_Email__c configured. ' +
                'Production: fix the Contact.Email data on the related record. ' +
                'Demo/Dev: run scripts/setup_email_config.apex to populate the Custom Setting.'
            );
        }
        return cfg.Default_Fallback_Email__c;
    }

    public class EmailFallbackException extends Exception {}
}
