// Regenerate the branded MSA PDF for Contract 00000301 with the
// updated controller (Subtotal / Discount / VAT / Grand Total in EUR).
// Removes prior stale PDFs first to avoid clutter.

Id contractId = [SELECT Id FROM Contract WHERE ContractNumber = '00000301' LIMIT 1].Id;

// Find prior MSA PDFs attached to this Contract and delete them
List<ContentDocumentLink> stale = [
    SELECT Id, ContentDocumentId, ContentDocument.Title
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :contractId
      AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'
];
List<Id> docIds = new List<Id>();
for (ContentDocumentLink cdl : stale) {
    System.debug('Deleting stale PDF: ' + cdl.ContentDocument.Title);
    docIds.add(cdl.ContentDocumentId);
}
if (!docIds.isEmpty()) {
    delete [SELECT Id FROM ContentDocument WHERE Id IN :docIds];
}

// Now regenerate via the existing invocable service
GenerateContractPdfService.Request req = new GenerateContractPdfService.Request();
req.contractId = contractId;
List<GenerateContractPdfService.Response> resps = GenerateContractPdfService.run(new List<GenerateContractPdfService.Request>{req});
for (GenerateContractPdfService.Response r : resps) {
    System.debug('Status=' + r.status + ' | Msg=' + r.message + ' | DocId=' + r.contentDocumentId);
}
