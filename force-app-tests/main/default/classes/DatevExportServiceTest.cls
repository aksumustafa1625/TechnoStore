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
}
