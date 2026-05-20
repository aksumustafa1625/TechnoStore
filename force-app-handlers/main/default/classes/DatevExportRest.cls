/**
 * DATEV Export REST endpoint — exposes DatevExportService over HTTP so the DATEV Buchungsstapel
 * CSV can be generated and retrieved via Postman (parallel to the SAP Postman collection), giving
 * the demo a recruiter-reproducible artifact for the DATEV integration (ADR-031).
 *
 * GET  /services/apexrest/datev/export?invoiceId=<Id>   -> returns the DATEV CSV as text/csv
 * POST /services/apexrest/datev/export  body { "invoiceId": "<Id>" } -> same
 *
 * Auth: standard Salesforce session / OAuth bearer token (Postman uses SF_ACCESS_TOKEN, same as
 * the existing TechnoStore Postman collection). No guest access — this is an authenticated demo tool.
 */
@RestResource(urlMapping='/datev/export/*')
global with sharing class DatevExportRest {

    @HttpGet
    global static void doGet() {
        Id invoiceId = resolveInvoiceId(RestContext.request.params.get('invoiceId'));
        respondWithCsv(invoiceId);
    }

    @HttpPost
    global static void doPost() {
        String invoiceIdStr = RestContext.request.params.get('invoiceId');
        if (String.isBlank(invoiceIdStr) && RestContext.request.requestBody != null) {
            try {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                    RestContext.request.requestBody.toString());
                if (body.containsKey('invoiceId')) invoiceIdStr = String.valueOf(body.get('invoiceId'));
            } catch (Exception ignored) { /* fall through to error */ }
        }
        respondWithCsv(resolveInvoiceId(invoiceIdStr));
    }

    private static Id resolveInvoiceId(String idStr) {
        // If no id supplied, default to the most recent posted Invoice (demo convenience).
        if (String.isNotBlank(idStr)) {
            try { return (Id) idStr; } catch (Exception e) { return null; }
        }
        List<Invoice> recent = [SELECT Id FROM Invoice WHERE Status = 'Posted' ORDER BY CreatedDate DESC LIMIT 1];
        if (recent.isEmpty()) recent = [SELECT Id FROM Invoice ORDER BY CreatedDate DESC LIMIT 1];
        return recent.isEmpty() ? null : recent[0].Id;
    }

    private static void respondWithCsv(Id invoiceId) {
        RestResponse resp = RestContext.response;
        if (invoiceId == null) {
            resp.statusCode = 400;
            resp.addHeader('Content-Type', 'application/json');
            resp.responseBody = Blob.valueOf('{"error":"No valid invoiceId; provide ?invoiceId=<Id> or a posted Invoice must exist."}');
            return;
        }
        try {
            String csv = DatevExportService.generateCsv(invoiceId);
            resp.statusCode = 200;
            resp.addHeader('Content-Type', 'text/csv; charset=UTF-8');
            resp.addHeader('Content-Disposition', 'attachment; filename="DATEV_Buchungsstapel.csv"');
            resp.responseBody = Blob.valueOf(csv);
        } catch (Exception e) {
            resp.statusCode = 500;
            resp.addHeader('Content-Type', 'application/json');
            resp.responseBody = Blob.valueOf('{"error":"' + e.getMessage().replace('"', '\\"') + '"}');
        }
    }
}
