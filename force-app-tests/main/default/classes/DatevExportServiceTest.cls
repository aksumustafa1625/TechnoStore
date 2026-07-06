/**
 * Unit tests for DatevExportService (ADR-031 — DATEV EXTF v700 / SKR04 CSV export).
 *
 * COVERAGE SHAPE
 *   - Account-side debitor field: pre-assigned values persist idempotently, SKR04 range
 *     (10000-69999) round-trips, bulk sequential assignment stays unique, and the
 *     max-scan SOQL that `allocateDebitor` performs lands where we expect (proves the
 *     algorithm's data input even though we cannot invoke the private method directly).
 *   - Invoice-driven entry points (`generateCsv`, `exportFromButton`, invocable `export`)
 *     exercise the "Invoice not found" branch. Native Invoice records CANNOT be created
 *     via Apex DML (documented in TestDataFactory — Salesforce Industries Billing forces
 *     REST creation), so every entry point that starts with a `SELECT ... FROM Invoice`
 *     lands in the missing-row branch: `generateCsv` propagates System.QueryException,
 *     `doExport` catches it → Result.status = 'Error', `export` invocable produces one
 *     Error Result per Request, empty/bulk lists are handled cleanly.
 *
 * COVERAGE GAP — TS-TEST-009
 *   The CSV formatter (`buildBuchungsstapel`) and its helpers (`germanDecimal`, `pad2`,
 *   `q`, `allocateDebitor`) are `private` and NOT `@TestVisible`. That means the
 *   behavioural contract of the DATEV EXTF v700 payload — EXTF/700/21 header row,
 *   semicolon separator, comma decimal, DDMM Belegdatum, SKR04 revenue account 4400,
 *   quoted-and-escaped text fields, CRLF row endings, UTF-8 BOM prefix on the Blob —
 *   cannot be verified from tests today. Two ways to close the gap:
 *     (a) Promote the helpers to `@TestVisible` (adds no runtime surface, unlocks pure
 *         string assertions on the CSV rows).
 *     (b) Add an integration test that provisions Invoices via REST /invoices and drives
 *         the real end-to-end path (parallel to TS-TEST-003).
 *   Tracked as TS-TEST-009 in the test roadmap.
 */
@IsTest
private class DatevExportServiceTest {

    // ---------- @TestSetup: three Accounts modelling the debitor states ----------

    @TestSetup
    static void seed() {
        // Account 1 — no debitor number (auto-allocation candidate)
        Account a1 = new Account(
            Name              = 'Debitor Free GmbH',
            BillingCountry    = 'Germany',
            BillingCity       = 'Berlin',
            BillingStreet     = 'Musterstrasse 1',
            BillingPostalCode = '10115'
        );
        // Account 2 — pre-assigned debitor 10005 (idempotency + max-scan anchor)
        Account a2 = new Account(
            Name                     = 'Existing Debitor AG',
            BillingCountry           = 'Germany',
            BillingCity              = 'Munich',
            BillingStreet            = 'Beispielweg 2',
            BillingPostalCode        = '80331',
            DATEV_Debitor_Number__c  = '10005'
        );
        // Account 3 — pre-assigned debitor 10003 (proves max, not last, is picked)
        Account a3 = new Account(
            Name                     = 'Middle Debitor UG',
            BillingCountry           = 'Germany',
            BillingCity              = 'Hamburg',
            BillingStreet            = 'Testallee 3',
            BillingPostalCode        = '20095',
            DATEV_Debitor_Number__c  = '10003'
        );
        insert new List<Account>{ a1, a2, a3 };
    }

    // ---------- Helpers ----------

    /** Well-formed Invoice Id that resolves to zero rows. */
    private static Id fakeInvoiceId() {
        String prefix = Schema.SObjectType.Invoice.getKeyPrefix();
        return Id.valueOf(prefix + '000000000000');
    }

    private static DatevExportService.Request buildRequest(Id invoiceId) {
        DatevExportService.Request req = new DatevExportService.Request();
        req.invoiceId = invoiceId;
        return req;
    }

    // ---------- Debitor allocation — Account-side (testable) ----------

    @IsTest
    static void debitorAllocation_newAccount_hasNullDebitorBySetup() {
        // Precondition for allocation: the "fresh" Account starts with a null debitor,
        // making it a candidate for `allocateDebitor` (which would stamp 10006 given
        // seeded max = 10005).
        Account a = [SELECT DATEV_Debitor_Number__c FROM Account
                     WHERE Name = 'Debitor Free GmbH' LIMIT 1];
        System.assertEquals(null, a.DATEV_Debitor_Number__c,
            'Seed Account 1 must have null debitor to serve as an allocation candidate');
    }

    @IsTest
    static void debitorAllocation_existingDebitor_isPreserved_idempotent() {
        // Idempotency: an Account with a pre-assigned debitor must round-trip unchanged.
        // (When invoked from `generateCsv`, the pre-existing value would short-circuit
        // the allocation branch — the algorithm depends on this round-trip.)
        Account a = [SELECT DATEV_Debitor_Number__c FROM Account
                     WHERE Name = 'Existing Debitor AG' LIMIT 1];
        System.assertEquals('10005', a.DATEV_Debitor_Number__c,
            'Pre-assigned debitor 10005 must persist verbatim on insert');
    }

    @IsTest
    static void debitorAllocation_DEBITOR_START_10001_roundTrips() {
        // Documents the private DEBITOR_START (10001) — the first value the algorithm
        // returns when no other Accounts carry a debitor.
        Account a = new Account(
            Name                     = 'SKR04 First',
            DATEV_Debitor_Number__c  = '10001'
        );
        insert a;

        Account queried = [SELECT DATEV_Debitor_Number__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('10001', queried.DATEV_Debitor_Number__c,
            'DEBITOR_START (10001) must round-trip through the field intact');
    }

    @IsTest
    static void debitorAllocation_bulkSequentialAssignment_isUnique() {
        // The allocator returns max+1 per invocation, producing unique sequential
        // debitors. We model that at the field level with five hand-picked values.
        List<Account> batch = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            batch.add(new Account(
                Name                     = 'Bulk Account ' + i,
                DATEV_Debitor_Number__c  = String.valueOf(20001 + i)
            ));
        }
        insert batch;

        Set<String> debitors = new Set<String>();
        for (Account a : [SELECT DATEV_Debitor_Number__c FROM Account
                          WHERE Name LIKE 'Bulk Account%']) {
            debitors.add(a.DATEV_Debitor_Number__c);
        }
        System.assertEquals(5, debitors.size(),
            'Five sequentially-assigned debitors must be unique');
        System.assert(debitors.contains('20001'),
            'First allocation 20001 must persist. Got: ' + debitors);
        System.assert(debitors.contains('20005'),
            'Fifth allocation 20005 must persist. Got: ' + debitors);
    }

    @IsTest
    static void debitorAllocation_maxScan_landsAt_10005_nextWouldBe_10006() {
        // `allocateDebitor` scans MAX(DATEV_Debitor_Number__c) across every Account and
        // returns max+1. Seed has 10003 and 10005 → max = 10005 → next = 10006. We can't
        // invoke the private method (TS-TEST-009 gap), but we CAN reproduce its SOQL
        // input and prove the max lands where the algorithm would.
        Integer maxSeen = 0;
        for (Account a : [SELECT DATEV_Debitor_Number__c FROM Account
                          WHERE DATEV_Debitor_Number__c != null]) {
            Integer n = Integer.valueOf(a.DATEV_Debitor_Number__c);
            if (n > maxSeen) maxSeen = n;
        }
        System.assertEquals(10005, maxSeen,
            'Max of seeded debitors must be 10005 → allocateDebitor would return 10006');
    }

    // ---------- generateCsv — public helper used by the REST endpoint ----------

    @IsTest
    static void generateCsv_missingInvoice_throwsQueryException() {
        // `generateCsv` assigns the SOQL result to a single Invoice variable — no rows
        // triggers System.QueryException. The method has no try/catch of its own; it
        // relies on `doExport` to translate the exception into a Result at the button
        // surface. Callers of the raw helper (e.g. REST) must expect the throw.
        Boolean threw = false;
        try {
            DatevExportService.generateCsv(fakeInvoiceId());
        } catch (QueryException e) {
            threw = true;
            System.assertNotEquals(null, e.getMessage(),
                'QueryException must carry a message');
        }
        System.assert(threw,
            'generateCsv must throw QueryException when the Invoice is not found');
    }

    // ---------- exportFromButton — LWC-invoked path (catches into Result) ----------

    @IsTest
    static void exportFromButton_missingInvoice_returnsErrorResult() {
        Test.startTest();
        DatevExportService.Result r = DatevExportService.exportFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertNotEquals(null, r,
            'exportFromButton must always return a Result — never null');
        System.assertEquals('Error', r.status,
            'Missing Invoice must map to Error status (doExport catches the QueryException)');
        System.assertNotEquals(null, r.message,
            'Error Result must carry an explanatory message');
        System.assert(r.message.contains('QueryException'),
            'Error message must surface the underlying exception type. Got: ' + r.message);
    }

    @IsTest
    static void exportFromButton_missingInvoice_noContentVersionAttached() {
        // The doExport error branch must NOT insert a ContentVersion (the CSV attachment
        // step is downstream of the CSV generation, which threw). Any leaked CV would be
        // an orphan against a non-existent Invoice.
        Integer before = [SELECT COUNT() FROM ContentVersion];

        Test.startTest();
        DatevExportService.exportFromButton(fakeInvoiceId());
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM ContentVersion];
        System.assertEquals(before, after,
            'No ContentVersion (CSV attachment) may be created on the error branch');
    }

    @IsTest
    static void exportFromButton_missingInvoice_invoiceIdEchoedOnResult() {
        // Result.invoiceId is stamped BEFORE the try (so a caller can correlate an Error
        // Result back to the Invoice that failed).
        Id ghost = fakeInvoiceId();
        DatevExportService.Result r = DatevExportService.exportFromButton(ghost);
        System.assertEquals(ghost, r.invoiceId,
            'Result.invoiceId must echo the requested Id even on the error branch');
    }

    // ---------- export — @InvocableMethod surface (Flow-callable) ----------

    @IsTest
    static void export_invocable_missingInvoice_returnsOneErrorPerRequest() {
        List<DatevExportService.Result> results = DatevExportService.export(
            new List<DatevExportService.Request>{ buildRequest(fakeInvoiceId()) }
        );

        System.assertEquals(1, results.size(),
            'One Request must produce one Result');
        System.assertEquals('Error', results[0].status,
            'Missing Invoice via invocable surface must map to Error');
        System.assertNotEquals(null, results[0].message,
            'Error Result must carry a message');
    }

    @IsTest
    static void export_invocable_bulkMissingInvoices_eachReturnsError() {
        // Bulk safety: three missing Invoices must produce three Error Results without
        // any one bad row aborting the batch.
        List<DatevExportService.Request> reqs = new List<DatevExportService.Request>();
        for (Integer i = 0; i < 3; i++) {
            reqs.add(buildRequest(fakeInvoiceId()));
        }

        List<DatevExportService.Result> results = DatevExportService.export(reqs);

        System.assertEquals(3, results.size(),
            '3 Requests → 3 Results — no row may be silently dropped');
        for (DatevExportService.Result r : results) {
            System.assertEquals('Error', r.status,
                'Every missing-Invoice Result must be Error');
        }
    }

    @IsTest
    static void export_invocable_emptyRequestList_returnsEmptyResults() {
        List<DatevExportService.Result> results = DatevExportService.export(
            new List<DatevExportService.Request>()
        );
        System.assertEquals(0, results.size(),
            'Empty Request list must return an empty Results list — no NPE, no throw');
    }

    // ---------- CSV format coverage gap — TS-TEST-009 ----------
    //
    // buildBuchungsstapel, germanDecimal, pad2, q, and allocateDebitor are ALL `private`
    // in DatevExportService. The behavioural contract they encode:
    //
    //   Row 1 (EXTF header):  "EXTF";700;21;"Buchungsstapel";9;<now>;"";"RE";
    //                         "TechnoStore";"";1;1;<fyStart>;4;<period>;<period>;
    //                         "TechnoStore Export";"";1;;;"EUR";;;;;;""
    //   Row 2 (col header):   Umsatz (ohne Soll/Haben-Kz);Soll/Haben-Kennzeichen;
    //                         WKZ Umsatz;Kurs;Basis-Umsatz;WKZ Basis-Umsatz;Konto;
    //                         Gegenkonto (ohne BU-Schlüssel);BU-Schlüssel;Belegdatum;
    //                         Belegfeld 1;Belegfeld 2;Skonto;Buchungstext
    //   Row 3 (booking):      1449,00;"S";"EUR";;;;<debitor>;4400;;"1506";"<docNum>";
    //                         "";;"Rechnung <account>"
    //
    // Row separator: CRLF (\r\n). Blob prefix: EF BB BF (UTF-8 BOM). Debitor: Account
    // DATEV_Debitor_Number__c or the allocator's max+1. Revenue account: 4400 SKR04.
    //
    // None of this can be verified from tests today because the entry point that produces
    // the CSV (`generateCsv`) requires an Invoice (Apex DML blocked). Options:
    //
    //   Option A — @TestVisible promotions (recommended, zero runtime cost):
    //     * buildBuchungsstapel(Invoice inv, String debitor) → String
    //     * germanDecimal(Decimal v) → String
    //     * pad2(Integer n) → String
    //     * q(String s) → String
    //     * allocateDebitor(Id accountId) → String
    //   Option B — REST-based integration test that provisions Invoices via
    //     POST /services/data/vXX.0/invoices, mirroring TS-TEST-003.
    //
    // Filed as TS-TEST-009.

    @IsTest
    static void csvFormat_privateHelpers_coverageGap_TS_TEST_009_documented() {
        // Anchor: proves the invocable surface (Request/Result nested types) is still
        // shaped the way DATEV_Export_Result-consuming Flow / LWC expect. If a signature
        // drifts, this compile-fails and forces the coverage-gap doc to be revisited.
        Type req = DatevExportService.Request.class;
        Type res = DatevExportService.Result.class;
        System.assertNotEquals(null, req,
            'Request nested type must remain visible to Flow');
        System.assertNotEquals(null, res,
            'Result nested type must remain visible to Flow / Aura / LWC');
    }

    // ---------- CSV format coverage — TS-TEST-009 closed via @TestVisible injection --------
    //
    // Salesforce Industries Billing forbids `insert new Invoice(...)` in Apex DML. The
    // community-verified workaround (afigueiredo.medium.com JSON deserialization pattern)
    // builds an in-memory Invoice via JSON.deserialize (which does NOT go through the DML
    // pipeline) and injects it into the service through a `@TestVisible` seam. This lets
    // us exercise buildBuchungsstapel + germanDecimal + pad2 + q end-to-end against a real
    // Invoice sObject graph — no mock, no reflection, no altered production code path.

    /**
     * Builds a fake Invoice with an embedded BillingAccount by deserializing JSON. Bypasses
     * the "Can't create in Apex" restriction on standard Industries Billing Invoice records.
     */
    private static Invoice buildInvoiceForDatev(Id fakeId, Account acc, Decimal amountWithTax, Date invDate, String docNumber) {
        String debStr = (acc.DATEV_Debitor_Number__c == null) ? 'null'
            : '"' + String.valueOf(acc.DATEV_Debitor_Number__c) + '"';
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"' + String.valueOf(fakeId) + '",'
            + '"DocumentNumber":"' + docNumber + '",'
            + '"InvoiceDate":"' + invDate.year() + '-'
                + String.valueOf(invDate.month()).leftPad(2, '0') + '-'
                + String.valueOf(invDate.day()).leftPad(2, '0') + '",'
            + '"TotalAmountWithTax":' + amountWithTax + ','
            + '"TotalAmount":' + (amountWithTax / 1.19).setScale(2) + ','
            + '"BillingAccountId":"' + acc.Id + '",'
            + '"BillingAccount":{'
                + '"attributes":{"type":"Account"},'
                + '"Id":"' + acc.Id + '",'
                + '"Name":"' + String.escapeSingleQuotes(acc.Name).replace('"', '\\"') + '",'
                + '"DATEV_Debitor_Number__c":' + debStr
            + '}'
            + '}';
        return (Invoice) System.JSON.deserialize(json, Invoice.class);
    }

    /** Convenience overload: default amount / date / doc number. */
    private static Invoice buildInvoiceForDatev(Account acc) {
        return buildInvoiceForDatev(fakeInvoiceId(), acc, 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-001');
    }

    private static Account existingDebitorAccount() {
        return [SELECT Id, Name, DATEV_Debitor_Number__c FROM Account
                WHERE Name = 'Existing Debitor AG' LIMIT 1];
    }

    // ---------- Header row (EXTF v700 / category 21) ----------

    @IsTest
    static void generateCsv_headerRow_containsEXTF_700_21_Buchungsstapel() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String headerRow = csv.split('\r\n')[0];
        System.assert(headerRow.contains('"EXTF"'),
            'DATEV header must carry the quoted format tag "EXTF". Got: ' + headerRow);
        System.assert(headerRow.contains(';700;'),
            'DATEV header must carry version 700 (SKR04 Buchungsstapel format). Got: ' + headerRow);
        System.assert(headerRow.contains(';21;'),
            'DATEV header must carry category 21 (Buchungsstapel). Got: ' + headerRow);
        System.assert(headerRow.contains('"Buchungsstapel"'),
            'DATEV header must carry the quoted "Buchungsstapel" label. Got: ' + headerRow);
        System.assert(headerRow.contains('"EUR"'),
            'DATEV header must declare EUR currency. Got: ' + headerRow);
        System.assert(headerRow.contains('"TechnoStore"'),
            'DATEV header must carry the "TechnoStore" mandant name. Got: ' + headerRow);
    }

    // ---------- Amounts — German comma decimal (1449.00 → "1449,00") ----------

    @IsTest
    static void generateCsv_amountsUseCommaDecimal_not_period() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), existingDebitorAccount(), 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-001');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        // Row 3 = booking row (index 2 after header + column-name rows)
        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.startsWith('1449,00;'),
            'German locale requires comma decimal on Umsatz. Expected "1449,00;". Got: ' + bookingRow);
        System.assert(!bookingRow.startsWith('1449.00;'),
            'Booking row must NOT use period as decimal separator (DATEV rejects it). Got: ' + bookingRow);
    }

    @IsTest
    static void generateCsv_amountsUseTotalAmountWithTax_notTotalAmount() {
        // TotalAmountWithTax is set → must win over TotalAmount (the pre-VAT figure).
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), existingDebitorAccount(), 1000.00, Date.newInstance(2026, 6, 15), 'RE-2026-002');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.startsWith('1000,00;'),
            'Booking Umsatz must use TotalAmountWithTax (gross), not TotalAmount (net). Got: ' + bookingRow);
    }

    // ---------- Date — DDMM format (2026-06-15 → "1506") ----------

    @IsTest
    static void generateCsv_dateFormat_DDMM_zero_padded() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), existingDebitorAccount(), 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-003');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.contains(';"1506";'),
            'Belegdatum must be DDMM (day-then-month). Expected "1506" for 2026-06-15. Got: ' + bookingRow);
        System.assert(!bookingRow.contains(';"0615";'),
            'Belegdatum must NOT be MMDD. Got: ' + bookingRow);
    }

    @IsTest
    static void generateCsv_dateFormat_singleDigitDayMonth_padded() {
        // Jan 3 → "0301" (both parts must be zero-padded).
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), existingDebitorAccount(), 500.00, Date.newInstance(2026, 1, 3), 'RE-2026-004');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.contains(';"0301";'),
            'Belegdatum for Jan 3 must be "0301" (DD then MM, both padded). Got: ' + bookingRow);
    }

    // ---------- Separator + line endings ----------

    @IsTest
    static void generateCsv_semicolonSeparator_notComma() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        // Each row has >= 14 fields → >= 13 semicolons. Row 3 has exactly 13 semicolons
        // between 14 fields.
        String bookingRow = csv.split('\r\n')[2];
        Integer semicolons = bookingRow.length() - bookingRow.replace(';', '').length();
        System.assert(semicolons >= 13,
            'DATEV booking row must have >=13 semicolons (14 fields). Got ' + semicolons + ' in: ' + bookingRow);
    }

    @IsTest
    static void generateCsv_crlfLineEndings_notLF() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        // 3 CRLF terminators (header + column header + booking + trailing CRLF).
        // \r\n is 2 chars → each occurrence removes 2 chars, so count = diff / 2.
        Integer occurrences = (csv.length() - csv.replace('\r\n', '').length()) / 2;
        System.assertEquals(3, occurrences,
            'DATEV export must have exactly 3 CRLF line terminators (one per row). Got: ' + occurrences);
        System.assert(!csv.contains('\n\n'),
            'Blank lines are not permitted between DATEV rows');
    }

    // ---------- Text-field quoting + inner-quote escaping ----------

    @IsTest
    static void generateCsv_textFieldsQuoted_withEscapedInnerQuotes() {
        Account acc = new Account(
            Name                    = 'ACME "Quoted" GmbH',
            DATEV_Debitor_Number__c = '30001'
        );
        insert acc;
        acc = [SELECT Id, Name, DATEV_Debitor_Number__c FROM Account WHERE Id = :acc.Id];

        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), acc, 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-005');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        // Buchungstext = "Rechnung ACME ""Quoted"" GmbH" — inner quotes doubled per DATEV rules.
        System.assert(bookingRow.contains('""Quoted""'),
            'Inner double-quotes must be escaped by doubling ("" per DATEV/CSV convention). Got: ' + bookingRow);
        System.assert(bookingRow.contains('"Rechnung ACME ""Quoted"" GmbH"'),
            'Buchungstext must be wrapped in outer quotes with doubled inner quotes. Got: ' + bookingRow);
    }

    // ---------- Revenue account (SKR04 4400) ----------

    @IsTest
    static void generateCsv_revenueAccount_4400_SKR04() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        // Row shape: gross;S;EUR;;;;<debitor>;4400;;<DDMM>;<docNum>;;;<buchungstext>
        // Gegenkonto (8th field, after 7 semicolons) must equal 4400 unquoted (numeric).
        System.assert(bookingRow.contains(';4400;'),
            'Gegenkonto must be SKR04 revenue account 4400 (Erlöse 19% USt), unquoted. Got: ' + bookingRow);
    }

    @IsTest
    static void generateCsv_debitor_fromBillingAccount_10005() {
        // Existing Debitor AG carries 10005 → must appear as Konto (7th field).
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.contains(';10005;4400;'),
            'Konto (Debitor) must be 10005 immediately preceding Gegenkonto 4400. Got: ' + bookingRow);
    }

    // ---------- Buchungstext truncation ----------

    @IsTest
    static void generateCsv_buchungstext_truncatedAt60Chars() {
        // "Rechnung " prefix is 9 chars. Account name padded to 80 chars would produce
        // "Rechnung <80 chars>" = 89 chars → abbreviate(60) trims to 60 chars total
        // (57 chars + "..." per Apex's String.abbreviate contract).
        // Built via rightPad (safer than String.repeat across Apex API versions).
        String longName = ''.rightPad(80, 'A');
        Account acc = new Account(
            Name                    = longName,
            DATEV_Debitor_Number__c = '30002'
        );
        insert acc;
        acc = [SELECT Id, Name, DATEV_Debitor_Number__c FROM Account WHERE Id = :acc.Id];

        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), acc, 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-006');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        // Extract Buchungstext (last field on the row, wrapped in quotes).
        Integer lastQuoteEnd = bookingRow.length() - 1;
        Integer lastQuoteStart = bookingRow.lastIndexOf('"', lastQuoteEnd - 1);
        String buchungstext = bookingRow.substring(lastQuoteStart + 1, lastQuoteEnd);
        System.assert(buchungstext.length() <= 60,
            'Buchungstext must be abbreviated to <= 60 chars. Got length ' + buchungstext.length() + ': ' + buchungstext);
        System.assert(buchungstext.endsWith('...'),
            'Over-length Buchungstext must end with the "..." abbreviation marker. Got: ' + buchungstext);
    }

    // ---------- Column-header row ----------

    @IsTest
    static void generateCsv_columnHeader_containsDATEVGermanNames() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String colHeader = csv.split('\r\n')[1];
        // Sample of required DATEV column headings (v700 spec, category 21).
        System.assert(colHeader.contains('Umsatz (ohne Soll/Haben-Kz)'),
            'Column header must carry Umsatz label. Got: ' + colHeader);
        System.assert(colHeader.contains('Soll/Haben-Kennzeichen'),
            'Column header must carry Soll/Haben-Kennzeichen. Got: ' + colHeader);
        System.assert(colHeader.contains('Konto'),
            'Column header must include Konto. Got: ' + colHeader);
        System.assert(colHeader.contains('Belegdatum'),
            'Column header must include Belegdatum. Got: ' + colHeader);
        System.assert(colHeader.contains('Buchungstext'),
            'Column header must include Buchungstext. Got: ' + colHeader);
        System.assert(colHeader.contains('BU-Schlüssel'),
            'Column header must carry umlaut in BU-Schlüssel (proves UTF-8 handling upstream of BOM). Got: ' + colHeader);
    }

    // ---------- Belegfeld 1 = DocumentNumber quoted ----------

    @IsTest
    static void generateCsv_documentNumber_appearsQuoted_inBelegfeld1() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), existingDebitorAccount(), 1449.00, Date.newInstance(2026, 6, 15), 'RE-2026-XYZ');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        System.assert(bookingRow.contains('"RE-2026-XYZ"'),
            'Belegfeld 1 must carry the quoted DocumentNumber verbatim. Got: ' + bookingRow);
    }

    // ---------- exportFromButton happy path (via testSkipDml) ----------

    @IsTest
    static void exportFromButton_happyPath_returnsSuccessResult_withCsvPreview() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());
        DatevExportService.testSkipDml = true;

        Test.startTest();
        DatevExportService.Result r = DatevExportService.exportFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('Success', r.status,
            'Happy-path exportFromButton must return Success. Got status="' + r.status + '" message="' + r.message + '"');
        System.assertNotEquals(null, r.fileName,
            'Success Result must expose the generated file name');
        System.assert(r.fileName.startsWith('DATEV_Buchungsstapel_RE-2026-001_'),
            'File name must include the DocumentNumber. Got: ' + r.fileName);
        System.assert(r.fileName.endsWith('.csv'),
            'File name must end with .csv. Got: ' + r.fileName);
        System.assertNotEquals(null, r.csvPreview,
            'Success Result must expose a csvPreview for the LWC toast');
        System.assert(r.csvPreview.contains('"EXTF"'),
            'csvPreview must carry the EXTF header for visual confirmation. Got: ' + r.csvPreview);
    }

    @IsTest
    static void exportFromButton_utf8BomPrepended_toContentVersionBlob() {
        // ADR-031: the CSV Blob attached to ContentVersion must be prefixed with the UTF-8
        // BOM (EF BB BF) so DATEV / Excel render umlauts correctly. Verified byte-wise via
        // the @TestVisible testLastCsvBlob capture (which mirrors the exact bytes fed to
        // ContentVersion.VersionData just before insert).
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());
        DatevExportService.testSkipDml = true;

        Test.startTest();
        DatevExportService.exportFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertNotEquals(null, DatevExportService.testLastCsvBlob,
            'Happy path must populate testLastCsvBlob (the BOM-prefixed CSV Blob)');
        String hex = EncodingUtil.convertToHex(DatevExportService.testLastCsvBlob).toUpperCase();
        System.assert(hex.startsWith('EFBBBF'),
            'CSV Blob must start with UTF-8 BOM bytes EF BB BF. Got: ' + hex.substring(0, Math.min(20, hex.length())));
    }

    // ---------- Invocable surface happy path ----------

    @IsTest
    static void export_invocable_happyPath_returnsSuccess() {
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(existingDebitorAccount());
        DatevExportService.testSkipDml = true;

        Test.startTest();
        List<DatevExportService.Result> results = DatevExportService.export(
            new List<DatevExportService.Request>{ buildRequest(fakeInvoiceId()) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One Request must produce one Result');
        System.assertEquals('Success', results[0].status,
            'Happy-path invocable must map to Success. Got: ' + results[0].message);
        System.assert(results[0].fileName.endsWith('.csv'),
            'Success invocable Result must expose a .csv file name. Got: ' + results[0].fileName);
    }

    // ---------- allocateDebitor path (blank debitor → Account update) ----------

    @IsTest
    static void generateCsv_blankDebitor_triggersAllocation_stampsAccount() {
        // BillingAccount has no debitor → the code path branches through allocateDebitor,
        // which scans max existing (seed = 10005 → next = 10006) and updates the Account.
        Account fresh = [SELECT Id, Name, DATEV_Debitor_Number__c FROM Account
                         WHERE Name = 'Debitor Free GmbH' LIMIT 1];
        DatevExportService.testInvoiceOverride = buildInvoiceForDatev(
            fakeInvoiceId(), fresh, 1449.00, Date.newInstance(2026, 6, 15), 'RE-ALLOC-001');

        Test.startTest();
        String csv = DatevExportService.generateCsv(fakeInvoiceId());
        Test.stopTest();

        String bookingRow = csv.split('\r\n')[2];
        // The debitor written back must be 10006 (max 10005 + 1) and appear in the row.
        System.assert(bookingRow.contains(';10006;4400;'),
            'Allocated Debitor must be max(10005)+1 = 10006, adjacent to Gegenkonto 4400. Got: ' + bookingRow);

        Account after = [SELECT DATEV_Debitor_Number__c FROM Account WHERE Id = :fresh.Id];
        System.assertEquals('10006', after.DATEV_Debitor_Number__c,
            'allocateDebitor must persist the new debitor back to the Account (idempotent for future exports)');
    }
}
