/**
 * DATEV Export — generates a DATEV-konform "Buchungsstapel" CSV from a standard Invoice
 * (Industries Billing) and attaches it to the invoice as a ContentVersion (ADR-031).
 *
 * Operates on the same standard Invoice that carries the Stripe payment flow, SAP tax and
 * SAP payment reconciliation fields. Counterpart to LexofficeInvoiceService: DATEV CSV serves
 * the Steuerberater / enterprise accounting segment (tax advisor imports the file into DATEV
 * Kanzlei-Rechnungswesen), while lexoffice serves the SME cloud segment via real-time API.
 * Together they give TechnoStore dual DACH B2B finance coverage.
 *
 * Format: DATEV-Format "EXTF", version 700, category 21 (Buchungsstapel). Three sections:
 *   - Line 1: EXTF header (metadata)
 *   - Line 2: column header row (DATEV standard German names)
 *   - Line 3+: one booking row per invoice
 *
 * Chart of accounts: SKR04. Revenue 4400 (Erlöse 19% USt, auto-applies VAT); customer Debitor =
 * BillingAccount.DATEV_Debitor_Number__c (range 10000-69999), auto-allocated if missing.
 *
 * German locale: comma decimal (1449,00), Belegdatum DDMM, semicolon separator, quoted text.
 *
 * Production caveat (ADR-031): Steuerberater validates account mapping + Wirtschaftsjahr;
 * encoding should be Windows-1252 (here UTF-8 for portability).
 */
public with sharing class DatevExportService {

    private static final String REVENUE_ACCOUNT = '4400';   // SKR04 Erlöse 19% USt
    private static final Integer DEBITOR_START = 10001;     // first auto-allocated Debitor

    // @TestVisible seams — Salesforce Industries Billing forbids `insert new Invoice(...)` in
    // Apex DML (documented in TestDataFactory + TS-TEST-009). Tests build an in-memory Invoice
    // via JSON.deserialize (afigueiredo pattern) and inject it here so the CSV formatter can
    // be exercised end-to-end without a real Invoice row. `testSkipDml` short-circuits the
    // ContentVersion insert whose FirstPublishLocationId would fail against a fake Invoice Id.
    // `testLastCsvBlob` captures the BOM-prefixed payload for byte-level assertions.
    @TestVisible private static Invoice testInvoiceOverride = null;
    @TestVisible private static Boolean testSkipDml = false;
    @TestVisible private static Blob testLastCsvBlob = null;

    public class Result {
        @AuraEnabled @InvocableVariable public Id invoiceId;
        @AuraEnabled @InvocableVariable public Id contentVersionId;
        @AuraEnabled @InvocableVariable public String fileName;
        @AuraEnabled @InvocableVariable public String csvPreview;
        @AuraEnabled @InvocableVariable public String status;
        @AuraEnabled @InvocableVariable public String message;
    }

    public class Request {
        @InvocableVariable(label='Invoice Id' required=true)
        public Id invoiceId;
    }

    @InvocableMethod(label='Export Invoice to DATEV CSV' description='Generates a DATEV Buchungsstapel CSV (SKR04) and attaches it to the Invoice for the Steuerberater to import.')
    public static List<Result> export(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            results.add(doExport(r.invoiceId));
        }
        return results;
    }

    @AuraEnabled
    public static Result exportFromButton(Id invoiceId) {
        return doExport(invoiceId);
    }

    // Returns the full DATEV Buchungsstapel CSV without attaching it (used by the REST endpoint).
    public static String generateCsv(Id invoiceId) {
        Invoice inv;
        if (testInvoiceOverride != null) {
            inv = testInvoiceOverride;
        } else {
            inv = [
                SELECT Id, DocumentNumber, TotalAmount, TotalAmountWithTax, InvoiceDate,
                       BillingAccountId, BillingAccount.Name, BillingAccount.DATEV_Debitor_Number__c
                FROM Invoice WHERE Id = :invoiceId LIMIT 1
            ];
        }
        String debitor = inv.BillingAccount != null ? inv.BillingAccount.DATEV_Debitor_Number__c : null;
        if (String.isBlank(debitor) && inv.BillingAccountId != null) {
            debitor = allocateDebitor(inv.BillingAccountId);
        }
        if (String.isBlank(debitor)) debitor = String.valueOf(DEBITOR_START);
        return buildBuchungsstapel(inv, debitor);
    }

    private static Result doExport(Id invoiceId) {
        Result res = new Result();
        res.invoiceId = invoiceId;
        try {
            String csv = generateCsv(invoiceId);
            Invoice inv;
            if (testInvoiceOverride != null) {
                inv = testInvoiceOverride;
            } else {
                inv = [SELECT DocumentNumber FROM Invoice WHERE Id = :invoiceId LIMIT 1];
            }
            res.csvPreview = csv.abbreviate(1000);

            String fileName = 'DATEV_Buchungsstapel_' + inv.DocumentNumber + '_' +
                Datetime.now().format('yyyyMMdd') + '.csv';
            // Prepend a UTF-8 BOM (EF BB BF) so Excel and DATEV import interpret the encoding
            // correctly (umlauts like "BU-Schlüssel" render properly, not "BU-SchlÃ¼ssel"). ADR-031.
            // Built via hex concat because Apex Blob has no direct concatenation.
            Blob csvWithBom = EncodingUtil.convertFromHex('EFBBBF' + EncodingUtil.convertToHex(Blob.valueOf(csv)));
            testLastCsvBlob = csvWithBom;
            ContentVersion cv = new ContentVersion(
                Title = fileName,
                PathOnClient = fileName,
                VersionData = csvWithBom,
                FirstPublishLocationId = invoiceId
            );
            if (!testSkipDml) {
                insert cv;
                res.contentVersionId = cv.Id;
            }
            res.fileName = fileName;
            res.status = 'Success';
            res.message = 'DATEV CSV generated and attached: ' + fileName;
        } catch (Exception e) {
            res.status = 'Error';
            res.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return res;
    }

    private static String buildBuchungsstapel(Invoice inv, String debitor) {
        Date d = inv.InvoiceDate == null ? Date.today() : inv.InvoiceDate;
        Integer fiscalYear = d.year();
        String now = Datetime.now().format('yyyyMMddHHmmssSSS');
        String belegdatum = pad2(d.day()) + pad2(d.month()); // DDMM
        String fyStart = String.valueOf(fiscalYear) + '0101';
        String period = String.valueOf(fiscalYear) + pad2(d.month()) + pad2(d.day());
        Decimal amount = inv.TotalAmountWithTax != null ? inv.TotalAmountWithTax
            : (inv.TotalAmount != null ? inv.TotalAmount : 0);
        String gross = germanDecimal(amount);
        String accountName = inv.BillingAccount != null ? inv.BillingAccount.Name : 'TechnoStore Kunde';
        String buchungstext = ('Rechnung ' + accountName).abbreviate(60);

        List<String> header = new List<String>{
            q('EXTF'), '700', '21', q('Buchungsstapel'), '9', now, '', q('RE'), q('TechnoStore'),
            q(''), '1', '1', fyStart, '4', period, period, q('TechnoStore Export'),
            q(''), '1', '', '', q('EUR'), '', '', '', '', '', q('')
        };

        List<String> cols = new List<String>{
            'Umsatz (ohne Soll/Haben-Kz)', 'Soll/Haben-Kennzeichen', 'WKZ Umsatz', 'Kurs',
            'Basis-Umsatz', 'WKZ Basis-Umsatz', 'Konto', 'Gegenkonto (ohne BU-Schlüssel)',
            'BU-Schlüssel', 'Belegdatum', 'Belegfeld 1', 'Belegfeld 2', 'Skonto', 'Buchungstext'
        };

        List<String> row = new List<String>{
            gross,            // Umsatz (gross, comma decimal)
            q('S'),           // Soll/Haben-Kennzeichen
            q('EUR'),         // WKZ Umsatz
            '',               // Kurs
            '',               // Basis-Umsatz
            '',               // WKZ Basis-Umsatz
            debitor,          // Konto (Debitor)
            REVENUE_ACCOUNT,  // Gegenkonto (Erlöse 19% USt)
            '',               // BU-Schlüssel
            q(belegdatum),    // Belegdatum DDMM
            q(inv.DocumentNumber), // Belegfeld 1
            q(''),            // Belegfeld 2
            '',               // Skonto
            q(buchungstext)   // Buchungstext
        };

        return String.join(header, ';') + '\r\n'
             + String.join(cols, ';') + '\r\n'
             + String.join(row, ';') + '\r\n';
    }

    private static String allocateDebitor(Id accountId) {
        Integer maxUsed = DEBITOR_START - 1;
        for (Account a : [
            SELECT DATEV_Debitor_Number__c FROM Account WHERE DATEV_Debitor_Number__c != null
        ]) {
            try {
                Integer n = Integer.valueOf(a.DATEV_Debitor_Number__c);
                if (n > maxUsed) maxUsed = n;
            } catch (Exception ignored) { /* non-numeric, skip */ }
        }
        String next = String.valueOf(maxUsed + 1);
        update new Account(Id = accountId, DATEV_Debitor_Number__c = next);
        return next;
    }

    private static String germanDecimal(Decimal v) {
        return v.setScale(2).toPlainString().replace('.', ',');
    }

    private static String pad2(Integer n) {
        return n < 10 ? '0' + n : String.valueOf(n);
    }

    private static String q(String s) {
        return '"' + (s == null ? '' : s.replace('"', '""')) + '"';
    }
}
