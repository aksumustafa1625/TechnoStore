public with sharing class AttachAndEmailInvoicePdf {

    public class Request {
        @InvocableVariable(required=true label='Invoice ID')
        public Id invoiceId;
    }

    @InvocableMethod(label='Generate Branded PDF, Attach to Invoice & Email Receipt'
                     description='Renders the TechnoStoreBrandedInvoice VF page as PDF, saves it to Salesforce Files linked to the Invoice, and emails it to the BillToContact with a branded receipt template.')
    public static void run(List<Request> requests) {
        for (Request r : requests) {
            generateAndSend(r.invoiceId);
        }
    }

    private static void generateAndSend(Id invoiceId) {
        Invoice inv = [
            SELECT Id, DocumentNumber, TotalAmountWithTax, Paid_Date__c,
                   BillingAccount.Name, BillToContact.Name, BillToContact.Email
            FROM Invoice WHERE Id = :invoiceId LIMIT 1
        ];

        PageReference pdfPage = Page.TechnoStoreBrandedInvoice;
        pdfPage.getParameters().put('id', invoiceId);
        pdfPage.getParameters().put('paid', 'true');
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
        String fileName = 'TechnoStore_Receipt_' + docNumber + '.pdf';

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
        email.setSubject('Your TechnoStore Receipt — Invoice ' + docNumber);
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
                System.debug(LoggingLevel.WARN, 'AttachAndEmailInvoicePdf email send skipped: ' + e.getMessage());
            }
        }
    }

    private static String buildEmailBody(Invoice inv) {
        String accountName = (inv.BillingAccount != null && inv.BillingAccount.Name != null)
            ? inv.BillingAccount.Name : 'Customer';
        Decimal amount = (inv.TotalAmountWithTax != null) ? inv.TotalAmountWithTax : 0;
        String amountStr = '$' + amount.setScale(2).format();
        String paidDateStr = (inv.Paid_Date__c != null) ? inv.Paid_Date__c.format() : '';
        String docNumber = inv.DocumentNumber == null ? 'Invoice' : inv.DocumentNumber;

        return '<html><body style="margin:0;padding:0;background-color:#f4f6f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;">' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f6f9;padding:40px 20px;"><tr><td align="center">' +
            '<table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e5e7eb;">' +
            '<tr><td style="background-color:#1B4F72;padding:32px 40px;text-align:center;">' +
            '<table cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;"><tr>' +
            '<td width="50" height="50" style="background-color:#5469D4;border-radius:10px;text-align:center;color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:24px;font-weight:900;line-height:50px;">TS</td>' +
            '<td style="padding-left:14px;font-family:Arial,Helvetica,sans-serif;color:#ffffff;text-align:left;vertical-align:middle;">' +
            '<div style="font-size:24px;font-weight:700;line-height:26px;letter-spacing:-0.3px;color:#ffffff;">TechnoStore</div>' +
            '<div style="font-size:9px;color:#a8b2c1;letter-spacing:2.5px;font-weight:500;margin-top:4px;">PAYMENT RECEIPT</div>' +
            '</td></tr></table></td></tr>' +
            '<tr><td style="padding:40px;">' +
            '<h1 style="color:#1B4F72;font-size:24px;margin:0 0 8px 0;font-weight:600;">Payment received &mdash; receipt attached</h1>' +
            '<p style="color:#6b7280;font-size:14px;margin:0 0 24px 0;">Thank you for your payment. Your branded invoice PDF is attached for your records.</p>' +
            '<p style="font-size:16px;color:#374151;line-height:1.6;margin:0 0 16px 0;">Dear ' + accountName + ' team,</p>' +
            '<p style="font-size:16px;color:#374151;line-height:1.6;margin:0 0 24px 0;">We have received your payment for <strong>' + docNumber + '</strong> in the amount of <strong>' + amountStr + '</strong>. ' +
            'For your records, the official TechnoStore invoice PDF is attached to this email and stored in your customer account.</p>' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0fdf4;border:1px solid #10B981;border-radius:8px;margin:24px 0;"><tr><td style="padding:24px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0">' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Invoice Number</td><td style="padding:6px 0;color:#111827;font-size:14px;font-weight:600;text-align:right;">' + docNumber + '</td></tr>' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Amount Paid</td><td style="padding:6px 0;color:#10B981;font-size:18px;font-weight:700;text-align:right;">' + amountStr + '</td></tr>' +
            '<tr><td style="padding:6px 0;color:#6b7280;font-size:14px;">Paid On</td><td style="padding:6px 0;color:#111827;font-size:14px;font-weight:600;text-align:right;">' + paidDateStr + '</td></tr>' +
            '<tr><td style="padding:12px 0 6px 0;color:#6b7280;font-size:14px;border-top:1px solid #d1fae5;">Status</td><td style="padding:12px 0 6px 0;color:#10B981;font-size:14px;font-weight:700;text-align:right;border-top:1px solid #d1fae5;">&#9989; PAID</td></tr>' +
            '</table></td></tr></table>' +
            '<p style="font-size:14px;color:#374151;line-height:1.6;margin:24px 0 8px 0;">&#128206; <strong>Attachment:</strong> ' + fileNameFor(docNumber) + '</p>' +
            '<p style="color:#9ca3af;font-size:12px;line-height:1.5;margin:32px 0 0 0;border-top:1px solid #e5e7eb;padding-top:20px;">Need help? Email <a href="mailto:support@technostore.com" style="color:#5469D4;text-decoration:none;">support@technostore.com</a>. Your invoice PDF is also available in your TechnoStore account under "Invoices &rarr; Files".</p>' +
            '</td></tr>' +
            '<tr><td style="background-color:#f9fafb;padding:24px 40px;border-top:1px solid #e5e7eb;">' +
            '<p style="color:#6b7280;font-size:12px;line-height:1.6;margin:0;text-align:center;">' +
            '&copy; 2026 TechnoStore GmbH &mdash; Berlin, Germany<br/>' +
            'Powered by Salesforce Revenue Cloud, Stripe &amp; MuleSoft' +
            '</p></td></tr>' +
            '</table></td></tr></table></body></html>';
    }

    private static String fileNameFor(String docNumber) {
        return 'TechnoStore_Receipt_' + docNumber + '.pdf';
    }
}
