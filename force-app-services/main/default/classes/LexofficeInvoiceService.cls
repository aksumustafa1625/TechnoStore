/**
 * lexoffice Invoice Publisher — pushes a posted/paid TechnoStore Invoice (standard Industries
 * Billing object) to lexoffice (Lexware Office), Germany's #1 SME cloud accounting platform (ADR-030).
 *
 * Operates on the same standard Invoice that already carries the Stripe payment flow
 * (Stripe_Payment_URL__c, Payment Journey LWC), SAP tax (Tax_Engine_Used__c) and SAP payment
 * reconciliation fields — so lexoffice publishing is a natural next step in the same record's
 * lifecycle. Counterpart to DatevExportService (Steuerberater CSV); together they give
 * TechnoStore dual DACH B2B finance coverage.
 *
 * Flow (two callouts):
 *   1. POST /v1/contacts        — create a lexoffice customer from the Invoice's BillingAccount
 *   2. POST /v1/invoices?finalize=true — create the invoice with line items from InvoiceLine
 * On success, writes Lexoffice_Invoice_Id__c + Lexoffice_Status__c=Published +
 * Lexoffice_Published_At__c back to the Invoice.
 *
 * Auth: Bearer API key from Lexoffice_Config__c.getOrgDefaults().API_Key__c.
 *
 * Tax handling: line item unit prices are treated as GROSS (incl. 19% DE VAT) via
 * InvoiceLine.GrossUnitPrice so the figure matches what the customer saw. lexoffice
 * back-computes net + VAT. taxConditions.taxType = "gross".
 */
public with sharing class LexofficeInvoiceService {

    private static final String SOURCE = 'lexoffice';
    private static final Decimal DE_VAT_RATE = 19;

    public class Request {
        @InvocableVariable(label='Invoice Id' required=true)
        public Id invoiceId;
    }

    public class Result {
        @AuraEnabled @InvocableVariable public Id invoiceId;
        @AuraEnabled @InvocableVariable public String lexofficeInvoiceId;
        @AuraEnabled @InvocableVariable public String status;
        @AuraEnabled @InvocableVariable public String message;
    }

    @InvocableMethod(label='Publish Invoice to lexoffice' description='Creates a lexoffice contact + invoice from a standard Invoice. Records appear in the lexoffice web UI immediately.')
    public static List<Result> publish(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            results.add(doPublish(r.invoiceId));
        }
        return results;
    }

    @AuraEnabled
    public static Result publishFromButton(Id invoiceId) {
        return doPublish(invoiceId);
    }

    @future(callout=true)
    public static void publishAsync(Set<Id> invoiceIds) {
        for (Id invId : invoiceIds) {
            doPublish(invId);
        }
    }

    private static Result doPublish(Id invoiceId) {
        Result res = new Result();
        res.invoiceId = invoiceId;
        String correlationId = 'lexoffice-' + invoiceId + '-' + System.currentTimeMillis();

        Lexoffice_Config__c cfg = Lexoffice_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.API_Key__c)) {
            res.status = 'Error';
            res.message = 'Lexoffice_Config__c missing or API_Key__c blank.';
            return res;
        }
        String baseUrl = String.isBlank(cfg.API_Base_URL__c) ? 'https://api.lexoffice.io' : cfg.API_Base_URL__c;
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.removeEnd('/');

        List<Invoice> invs = [
            SELECT Id, DocumentNumber, TotalAmount, TotalAmountWithTax, InvoiceDate,
                   BillingAccountId, BillingAccount.Name,
                   BillingAccount.BillingStreet, BillingAccount.BillingCity,
                   BillingAccount.BillingPostalCode, BillingAccount.BillingCountry
            FROM Invoice WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) {
            res.status = 'Error';
            res.message = 'Invoice not found: ' + invoiceId;
            return res;
        }
        Invoice inv = invs[0];

        List<InvoiceLine> lines = [
            SELECT Id, Product2Id, Product2.Name, Description, Quantity,
                   GrossUnitPrice, UnitPrice, ChargeAmountWithTax
            FROM InvoiceLine WHERE InvoiceId = :invoiceId
        ];

        try {
            String contactId = createContact(baseUrl, cfg.API_Key__c, inv, correlationId);
            String lexInvoiceId = createInvoice(baseUrl, cfg.API_Key__c, inv, lines, contactId, correlationId);

            update new Invoice(
                Id = inv.Id,
                Lexoffice_Invoice_Id__c = lexInvoiceId,
                Lexoffice_Status__c = 'Published',
                Lexoffice_Published_At__c = System.now()
            );

            res.lexofficeInvoiceId = lexInvoiceId;
            res.status = 'Success';
            res.message = 'Published to lexoffice. Invoice id: ' + lexInvoiceId;
        } catch (Exception e) {
            try {
                update new Invoice(Id = inv.Id, Lexoffice_Status__c = 'Publish Failed');
            } catch (Exception ignored) { /* status update is non-critical */ }

            IntegrationErrorLogger.log(SOURCE, 'publishInvoice', e, invoiceId, correlationId);
            res.status = 'Error';
            res.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return res;
    }

    private static String createContact(String baseUrl, String apiKey, Invoice inv, String correlationId) {
        Account acct = inv.BillingAccount;
        Map<String, Object> billing = new Map<String, Object>{
            'street' => emptyToNull(acct != null ? acct.BillingStreet : null),
            'zip' => emptyToNull(acct != null ? acct.BillingPostalCode : null),
            'city' => emptyToNull(acct != null ? acct.BillingCity : null),
            'countryCode' => countryCode(acct != null ? acct.BillingCountry : null)
        };
        Map<String, Object> payload = new Map<String, Object>{
            'version' => 0,
            'roles' => new Map<String, Object>{ 'customer' => new Map<String, Object>() },
            'company' => new Map<String, Object>{ 'name' => acct != null ? acct.Name : 'TechnoStore Customer' },
            'addresses' => new Map<String, Object>{ 'billing' => new List<Object>{ billing } }
        };

        HttpResponse resp = doPost(baseUrl + '/v1/contacts', apiKey, JSON.serialize(payload));
        if (resp.getStatusCode() != 200 && resp.getStatusCode() != 201) {
            IntegrationErrorLogger.logHttpFailure(SOURCE, 'createContact', resp, JSON.serialize(payload), inv.Id, correlationId);
            throw new LexofficeException('Contact create failed: HTTP ' + resp.getStatusCode() + ' ' + resp.getBody().abbreviate(300));
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        return String.valueOf(body.get('id'));
    }

    private static String createInvoice(String baseUrl, String apiKey, Invoice inv,
                                        List<InvoiceLine> lines, String contactId, String correlationId) {
        List<Object> lineItems = new List<Object>();
        if (!lines.isEmpty()) {
            for (InvoiceLine il : lines) {
                Decimal grossUnit = il.GrossUnitPrice != null ? il.GrossUnitPrice
                    : (il.UnitPrice != null ? il.UnitPrice : 0);
                String itemName = il.Product2 != null && String.isNotBlank(il.Product2.Name)
                    ? il.Product2.Name
                    : (String.isNotBlank(il.Description) ? il.Description : 'TechnoStore Item');
                lineItems.add(new Map<String, Object>{
                    'type' => 'custom',
                    'name' => itemName,
                    'quantity' => il.Quantity != null ? il.Quantity : 1,
                    'unitName' => 'Stück',
                    'unitPrice' => new Map<String, Object>{
                        'currency' => 'EUR',
                        'grossAmount' => grossUnit,
                        'taxRatePercentage' => DE_VAT_RATE
                    }
                });
            }
        } else {
            Decimal gross = inv.TotalAmountWithTax != null ? inv.TotalAmountWithTax
                : (inv.TotalAmount != null ? inv.TotalAmount : 0);
            lineItems.add(new Map<String, Object>{
                'type' => 'custom',
                'name' => 'TechnoStore Invoice ' + inv.DocumentNumber,
                'quantity' => 1,
                'unitName' => 'Stück',
                'unitPrice' => new Map<String, Object>{
                    'currency' => 'EUR',
                    'grossAmount' => gross,
                    'taxRatePercentage' => DE_VAT_RATE
                }
            });
        }

        String voucherDate = isoDate(inv.InvoiceDate);
        Map<String, Object> address = new Map<String, Object>{
            'contactId' => contactId,
            'name' => inv.BillingAccount != null ? inv.BillingAccount.Name : 'TechnoStore Customer',
            'countryCode' => countryCode(inv.BillingAccount != null ? inv.BillingAccount.BillingCountry : null)
        };

        Map<String, Object> payload = new Map<String, Object>{
            'voucherDate' => voucherDate,
            'address' => address,
            'lineItems' => lineItems,
            'totalPrice' => new Map<String, Object>{ 'currency' => 'EUR' },
            'taxConditions' => new Map<String, Object>{ 'taxType' => 'gross' },
            'shippingConditions' => new Map<String, Object>{
                'shippingDate' => voucherDate,
                'shippingType' => 'service'
            },
            'title' => 'Rechnung',
            'introduction' => 'Invoice for your TechnoStore order ' + inv.DocumentNumber,
            'remark' => 'Vielen Dank für Ihren Auftrag. — TechnoStore'
        };

        HttpResponse resp = doPost(baseUrl + '/v1/invoices?finalize=true', apiKey, JSON.serialize(payload));
        if (resp.getStatusCode() != 200 && resp.getStatusCode() != 201) {
            IntegrationErrorLogger.logHttpFailure(SOURCE, 'createInvoice', resp, JSON.serialize(payload), inv.Id, correlationId);
            throw new LexofficeException('Invoice create failed: HTTP ' + resp.getStatusCode() + ' ' + resp.getBody().abbreviate(300));
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        return String.valueOf(body.get('id'));
    }

    private static HttpResponse doPost(String endpoint, String apiKey, String jsonBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        req.setBody(jsonBody);
        return new Http().send(req);
    }

    // lexoffice expects ISO 8601 with offset, e.g. 2026-05-21T00:00:00.000+02:00
    private static String isoDate(Date d) {
        Date useDate = d == null ? Date.today() : d;
        return Datetime.newInstance(useDate.year(), useDate.month(), useDate.day(), 0, 0, 0)
            .format('yyyy-MM-dd') + 'T00:00:00.000+02:00';
    }

    private static String countryCode(String country) {
        if (String.isBlank(country)) return 'DE';
        String c = country.trim().toLowerCase();
        if (c == 'germany' || c == 'deutschland' || c == 'de') return 'DE';
        if (c == 'austria' || c == 'österreich' || c == 'at') return 'AT';
        if (c == 'switzerland' || c == 'schweiz' || c == 'ch') return 'CH';
        if (c.length() == 2) return country.toUpperCase();
        return 'DE';
    }

    private static String emptyToNull(String s) {
        return String.isBlank(s) ? null : s;
    }

    public class LexofficeException extends Exception {}
}
