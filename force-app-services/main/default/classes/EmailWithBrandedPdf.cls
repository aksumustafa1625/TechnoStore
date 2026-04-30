public with sharing class EmailWithBrandedPdf {

    public class Request {
        @InvocableVariable(required=true label='Invoice ID')
        public Id invoiceId;
        @InvocableVariable(required=true label='Email HTML Body')
        public String emailHtmlBody;
        @InvocableVariable(required=true label='Email Subject')
        public String emailSubject;
    }

    @InvocableMethod(label='Email Customer with Branded Receipt PDF Attached'
                     description='Generates the post-payment branded RECEIPT PDF, saves it to Salesforce Files on the Invoice, and sends it as attachment along with the supplied HTML body.')
    public static void run(List<Request> requests) {
        for (Request r : requests) {
            try {
                execute(r);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'EmailWithBrandedPdf failed for invoice ' + r.invoiceId + ': ' + e.getMessage());
            }
        }
    }

    private static void execute(Request req) {
        Invoice inv = [
            SELECT Id, DocumentNumber, BillToContact.Email
            FROM Invoice WHERE Id = :req.invoiceId LIMIT 1
        ];

        PageReference pdfPage = Page.TechnoStoreBrandedInvoice;
        pdfPage.getParameters().put('id', req.invoiceId);
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

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;
        cv.IsMajorVersion = true;
        insert cv;

        ContentVersion saved = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = saved.ContentDocumentId;
        cdl.LinkedEntityId = req.invoiceId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;

        String recipient = (inv.BillToContact != null && inv.BillToContact.Email != null)
            ? inv.BillToContact.Email : 'demo-recipient@example.com';

        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
        efa.setFileName(fileName);
        efa.setBody(pdfBlob);
        efa.setContentType('application/pdf');

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { recipient });
        email.setSubject(req.emailSubject);
        email.setHtmlBody(req.emailHtmlBody);
        email.setFileAttachments(new Messaging.EmailFileAttachment[] { efa });

        Id oweId = lookupOrgWideEmailId();
        if (oweId != null) {
            email.setOrgWideEmailAddressId(oweId);
        }

        if (!Test.isRunningTest()) {
            try {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'EmailWithBrandedPdf email send skipped: ' + e.getMessage());
            }
        }
    }

    private static Id lookupOrgWideEmailId() {
        List<OrgWideEmailAddress> oweList = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE DisplayName = 'TechnoStore Billing' LIMIT 1
        ];
        return oweList.isEmpty() ? null : oweList[0].Id;
    }
}
