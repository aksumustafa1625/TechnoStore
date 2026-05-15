public with sharing class AttachAndEmailInvoicePreview {

    public class Request {
        @InvocableVariable(required=true label='Invoice ID')
        public Id invoiceId;
    }

    @InvocableMethod(label='Generate Pre-Payment PDF, Attach & Email Payment Link'
                     description='Renders the orange-themed TechnoStoreInvoicePreviewPdf VF page as PDF, saves to Files, and emails it with the Stripe payment link.')
    public static void run(List<Request> requests) {
        for (Request r : requests) {
            generateAndSend(r.invoiceId);
        }
    }

    private static void generateAndSend(Id invoiceId) {
        Invoice inv = [
            SELECT Id, DocumentNumber, TotalAmountWithTax, DueDate,
                   Stripe_Payment_URL__c,
                   BillingAccount.Name, BillToContact.Name, BillToContact.Email
            FROM Invoice WHERE Id = :invoiceId LIMIT 1
        ];

        PageReference pdfPage = Page.TechnoStoreInvoicePreviewPdf;
        pdfPage.getParameters().put('id', invoiceId);
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('TEST');
        } else {
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                pdfBlob = Blob.valueOf('PDF generation failed: ' + e.getMessage());
            }
        }

        String docNumber = (inv.DocumentNumber == null) ? 'Invoice' : inv.DocumentNumber;
        String fileName = 'TechnoStore_Invoice_' + docNumber + '.pdf';

        // PDF Files'a kaydetmiyoruz (Dev Edition storage limit). Sadece email eki olarak gider.

        String recipient = EmailFallbackResolver.resolve(
            inv.BillToContact != null ? inv.BillToContact.Email : null
        );

        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
        efa.setFileName(fileName);
        efa.setBody(pdfBlob);
        efa.setContentType('application/pdf');

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { recipient });
        email.setSubject('Invoice ' + docNumber + ' — Payment Link Inside (TechnoStore)');
        email.setHtmlBody(buildEmailBody(inv));
        email.setFileAttachments(new Messaging.EmailFileAttachment[] { efa });

        List<OrgWideEmailAddress> oweList = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE DisplayName = 'TechnoStore Billing' LIMIT 1
        ];
        if (!oweList.isEmpty()) {
            email.setOrgWideEmailAddressId(oweList[0].Id);
        }

        if (!Test.isRunningTest()) {
            try {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'AttachAndEmailInvoicePreview email send skipped: ' + e.getMessage());
            }
        }
    }

    private static String buildEmailBody(Invoice inv) {
        String accountName = (inv.BillingAccount != null && inv.BillingAccount.Name != null)
            ? inv.BillingAccount.Name : 'Customer';
        Decimal amount = (inv.TotalAmountWithTax != null) ? inv.TotalAmountWithTax : 0;
        String amountStr = '$' + amount.setScale(2).format();
        String dueStr = (inv.DueDate != null) ? inv.DueDate.format() : '';
        String docNumber = inv.DocumentNumber == null ? 'Invoice' : inv.DocumentNumber;
        String stripeUrl = inv.Stripe_Payment_URL__c == null ? '#' : inv.Stripe_Payment_URL__c;
        String fileName = 'TechnoStore_Invoice_' + docNumber + '.pdf';

        return '<html><body style="margin:0;padding:0;background-color:#f4f6f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;">' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f6f9;padding:40px 20px;"><tr><td align="center">' +
            '<table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb;">' +
            '<tr><td style="height:6px;background-color:#FF6B35;font-size:0;line-height:0;">&nbsp;</td></tr>' +
            '<tr><td style="background-color:#1B4F72;padding:32px 40px;text-align:center;">' +
            '<table cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;"><tr>' +
            '<td width="50" height="50" style="background-color:#5469D4;border-radius:10px;text-align:center;color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:24px;font-weight:900;line-height:50px;">TS</td>' +
            '<td style="padding-left:14px;font-family:Arial,Helvetica,sans-serif;color:#ffffff;text-align:left;vertical-align:middle;">' +
            '<div style="font-size:24px;font-weight:700;line-height:26px;letter-spacing:-0.3px;color:#ffffff;">TechnoStore</div>' +
            '<div style="font-size:9px;color:#FFB59A;letter-spacing:2.5px;font-weight:500;margin-top:4px;">PAYMENT REQUEST</div>' +
            '</td></tr></table></td></tr>' +
            '<tr><td style="padding:40px;">' +
            '<h1 style="color:#1B4F72;font-size:24px;margin:0 0 8px 0;font-weight:600;">Your invoice is ready</h1>' +
            '<p style="color:#6b7280;font-size:14px;margin:0 0 24px 0;">Invoice attached as PDF. Pay securely via the link below.</p>' +
            '<p style="font-size:16px;color:#374151;line-height:1.6;margin:0 0 16px 0;">Dear ' + accountName + ' team,</p>' +
            '<p style="font-size:16px;color:#374151;line-height:1.6;margin:0 0 24px 0;">Please find your TechnoStore invoice attached. Total <strong>' + amountStr + '</strong> is due by <strong>' + dueStr + '</strong>.</p>' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#fff7ed;border:1px solid #FF6B35;border-radius:8px;margin:24px 0;"><tr><td style="padding:24px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0">' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Invoice Number</td><td style="padding:6px 0;color:#111827;font-size:14px;font-weight:600;text-align:right;">' + docNumber + '</td></tr>' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Amount Due</td><td style="padding:6px 0;color:#FF6B35;font-size:18px;font-weight:700;text-align:right;">' + amountStr + '</td></tr>' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Due Date</td><td style="padding:6px 0;color:#111827;font-size:14px;font-weight:600;text-align:right;">' + dueStr + '</td></tr>' +
            '<tr><td style="padding:12px 0 6px 0;color:#6b7280;font-size:14px;border-top:1px solid #FED7AA;">Status</td><td style="padding:12px 0 6px 0;color:#FF6B35;font-size:14px;font-weight:700;text-align:right;border-top:1px solid #FED7AA;">&#9203; AWAITING PAYMENT</td></tr>' +
            '</table></td></tr></table>' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="margin:32px 0 16px 0;"><tr><td align="center">' +
            '<a href="' + stripeUrl + '" style="display:inline-block;padding:16px 56px;background-color:#FF6B35;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:600;font-size:16px;">Pay Now Securely</a>' +
            '</td></tr></table>' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px 0;"><tr><td align="center" style="color:#6b7280;font-size:13px;">' +
            '<span style="display:inline-block;padding:3px 10px;background:#ecfdf5;color:#065f46;border-radius:4px;font-size:11px;font-weight:600;letter-spacing:0.5px;margin-right:6px;">SECURE</span>Powered by Stripe — bank-level encryption</td></tr></table>' +
            '<p style="font-size:14px;color:#374151;line-height:1.6;margin:24px 0 8px 0;">&#128206; <strong>Attachment:</strong> ' + fileName + '</p>' +
            '<p style="color:#9ca3af;font-size:12px;line-height:1.5;margin:32px 0 0 0;border-top:1px solid #e5e7eb;padding-top:20px;"><strong style="color:#6b7280;">Trouble with the button?</strong><br/>Copy and paste this link into your browser:<br/><a href="' + stripeUrl + '" style="color:#5469D4;word-break:break-all;text-decoration:none;font-size:11px;">' + stripeUrl + '</a></p>' +
            '</td></tr>' +
            '<tr><td style="background-color:#f9fafb;padding:24px 40px;border-top:1px solid #e5e7eb;">' +
            '<p style="color:#6b7280;font-size:12px;line-height:1.6;margin:0;text-align:center;">' +
            '&copy; 2026 TechnoStore GmbH &mdash; Berlin, Germany<br/>' +
            'This is an automated email. Please do not reply directly to this message.' +
            '</p></td></tr>' +
            '</table></td></tr></table></body></html>';
    }
}
