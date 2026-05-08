/**
 * Renders the TechnoStoreContractPdf VF page as a PDF and attaches it to
 * the Contract via ContentDocumentLink (LinkedEntityId = Contract.Id).
 *
 * Bypasses the broken native CLM "Generate Document" path. The PDF is
 * subsequently picked up by DocuSignSendForSignatureService when the user
 * clicks "Send Via DocuSign".
 */
public with sharing class GenerateContractPdfService {

    public class Request {
        @InvocableVariable(required=true label='Contract ID')
        public Id contractId;
    }

    public class Response {
        @InvocableVariable(label='ContentDocumentId')
        public Id contentDocumentId;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Generate Branded Contract PDF'
                     description='Renders TechnoStoreContractPdf VF as PDF and links to the Contract for downstream DocuSign send.')
    public static List<Response> run(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request r : requests) {
            results.add(execute(r));
        }
        return results;
    }

    private static Response execute(Request req) {
        Response resp = new Response();
        try {
            Contract c = [SELECT Id, ContractNumber FROM Contract WHERE Id = :req.contractId LIMIT 1];

            // Delete prior MSA PDFs attached to this Contract so each regen replaces the stale one
            // (instead of accumulating; the flow re-fires on AccountId/StartDate/EndDate/ContractTerm change).
            List<ContentDocumentLink> priorLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :req.contractId
                  AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'
            ];
            if (!priorLinks.isEmpty()) {
                Set<Id> docIds = new Set<Id>();
                for (ContentDocumentLink cdl : priorLinks) docIds.add(cdl.ContentDocumentId);
                delete [SELECT Id FROM ContentDocument WHERE Id IN :docIds];
            }

            PageReference pdfPage = Page.TechnoStoreContractPdf;
            pdfPage.getParameters().put('id', req.contractId);
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('TEST');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            String docNumber = c.ContractNumber == null ? 'C-DRAFT' : c.ContractNumber;
            String fileName = 'TechnoStore_MSA_' + docNumber + '.pdf';

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            insert cv;

            ContentVersion saved = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = saved.ContentDocumentId;
            cdl.LinkedEntityId = req.contractId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;

            resp.contentDocumentId = saved.ContentDocumentId;
            resp.status = 'Success';
            resp.message = 'Contract PDF generated and attached: ' + fileName;
        } catch (Exception e) {
            resp.status = 'Error';
            resp.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return resp;
    }
}
