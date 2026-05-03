public with sharing class DocuSignSendForSignatureService {

    private static final String DOCUSIGN_ACCOUNT_ID = '47481170';

    public class Request {
        @InvocableVariable(required=true label='Contract Id')
        public Id contractId;
        @InvocableVariable(required=true label='Recipient Name')
        public String recipientName;
        @InvocableVariable(required=true label='Recipient Email')
        public String recipientEmail;
        @InvocableVariable(label='Email Subject')
        public String emailSubject;
        @InvocableVariable(label='Email Message')
        public String emailMessage;
    }

    public class Response {
        @InvocableVariable(label='Envelope Id')
        public String envelopeId;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Send Contract via DocuSign' callout=true)
    public static List<Response> send(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request r : requests) {
            results.add(sendOne(r));
        }
        return results;
    }

    private static Response sendOne(Request r) {
        Response resp = new Response();
        try {
            ContentVersion pdf = findContractPdf(r.contractId);
            if (pdf == null) {
                resp.status = 'Error';
                resp.message = 'No active PDF document found for this contract. Generate the contract document first.';
                return resp;
            }

            String body = JSON.serialize(buildEnvelope(pdf, r));

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:DocuSign/restapi/v2.1/accounts/' + DOCUSIGN_ACCOUNT_ID + '/envelopes');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setBody(body);
            req.setTimeout(120000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 201) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.envelopeId = (String) parsed.get('envelopeId');
                resp.status = (String) parsed.get('status');
                resp.message = 'Envelope created and sent. Recipient will receive an email shortly.';

                update new Contract(Id = r.contractId, DocuSign_Envelope_Id__c = resp.envelopeId);
            } else {
                resp.status = 'Error';
                resp.message = 'DocuSign returned ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            resp.status = 'Error';
            resp.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return resp;
    }

    private static ContentVersion findContractPdf(Id contractId) {
        // PRIMARY: native CLM ContractDocumentVersion (when CLM Document Template flow is used)
        Set<Id> linkedEntityIds = new Set<Id>();
        for (ContractDocumentVersion v : [
            SELECT Id FROM ContractDocumentVersion
            WHERE ContractId = :contractId AND Status = 'Active'
            ORDER BY CreatedDate DESC LIMIT 1
        ]) {
            linkedEntityIds.add(v.Id);
        }

        // FALLBACK: PDFs attached directly to the Contract (when our custom GenerateContractPdfService is used)
        linkedEntityIds.add(contractId);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :linkedEntityIds
        ];
        if (links.isEmpty()) return null;

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);

        // Prefer the custom branded MSA PDF (TechnoStore_MSA_*) over any other contract PDF
        // (e.g. native CLM-generated documents). The custom PDF is the polished demo artifact.
        List<ContentVersion> brandedPdfs = [
            SELECT Id, Title, FileExtension, VersionData, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND FileExtension = 'pdf'
              AND Title LIKE 'TechnoStore_MSA%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!brandedPdfs.isEmpty()) return brandedPdfs[0];

        List<ContentVersion> pdfs = [
            SELECT Id, Title, FileExtension, VersionData, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND FileExtension = 'pdf'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return pdfs.isEmpty() ? null : pdfs[0];
    }

    private static Map<String, Object> buildEnvelope(ContentVersion pdf, Request r) {
        String subject = String.isBlank(r.emailSubject) ? 'Signature Request - ' + pdf.Title : r.emailSubject;
        String blurb = String.isBlank(r.emailMessage) ? 'Please review and sign this contract.' : r.emailMessage;

        return new Map<String, Object>{
            'emailSubject' => subject,
            'emailBlurb' => blurb,
            'status' => 'sent',
            'documents' => new List<Object>{
                new Map<String, Object>{
                    'documentBase64' => EncodingUtil.base64Encode(pdf.VersionData),
                    'name' => pdf.Title + '.pdf',
                    'fileExtension' => 'pdf',
                    'documentId' => '1'
                }
            },
            'recipients' => new Map<String, Object>{
                'signers' => new List<Object>{
                    new Map<String, Object>{
                        'email' => r.recipientEmail,
                        'name' => r.recipientName,
                        'recipientId' => '1',
                        'routingOrder' => '1',
                        'tabs' => new Map<String, Object>{
                            'signHereTabs' => new List<Object>{
                                new Map<String, Object>{
                                    'documentId' => '1',
                                    'pageNumber' => '1',
                                    'xPosition' => '100',
                                    'yPosition' => '600'
                                }
                            }
                        }
                    }
                }
            }
        };
    }
}
