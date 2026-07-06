/**
 * Unit tests for SapPaymentReconciliationService — CAMT.053 / ISO 20022 XML parser (ADR-025).
 *
 * The service is the SF side of the SAP FI payment-reconciliation loop:
 *   1. Parse CAMT.053 bank-statement XML into a list of CamtTransaction structs
 *   2. Keep only CRDT (credit) entries with a decimal amount
 *   3. Match each credit against an open Invoice via:
 *        a) EndToEndId contains an Invoice DocumentNumber
 *        b) RemittanceInformation Ustrd contains an Invoice DocumentNumber
 *        c) Amount within ±0.50 EUR of an open Invoice TotalAmount
 *   4. Stamp Payment_Method__c / SAP_Payment_Reference__c / SAP_Payment_Posted_At__c
 *
 * ------------------------------------------------------------------
 * PLATFORM LIMITATION — deferred coverage (TS-TEST-007)
 * ------------------------------------------------------------------
 * The class exercises the full match+stamp path only when there are open
 * Invoice records in the org. However, native `Invoice` records CANNOT be
 * inserted via Apex DML — Salesforce Industries Billing forces creation via
 * REST (`POST /services/data/vXX.0/invoices`) so that Billing Schedule +
 * line-item + tax-provider hooks fire atomically. See TestDataFactory.cls
 * for the FIELD_INTEGRITY_EXCEPTION note.
 *
 * As a result the following branches CANNOT be covered by these unit tests
 * and are deferred to TS-TEST-007 (REST-based integration harness):
 *   - matchTransaction Rule 1: EndToEndId → Invoice by DocumentNumber
 *   - matchTransaction Rule 2: Ustrd remittance → Invoice by DocumentNumber
 *   - matchTransaction Rule 3: amount within ±0.50 EUR tolerance
 *   - Payment_Method__c / SAP_Payment_Reference__c / SAP_Payment_Posted_At__c
 *     write-back on real Invoice records (Database.update result path)
 *   - "don't double-match same Invoice in one batch" dedupe rule
 *
 * What IS covered here (all reachable without Invoice DML):
 *   - CAMT.053 XML parse pipeline (Dom.Document recursion via Ntry lookup)
 *   - CRDT vs DBIT filter — debits skipped, credits kept
 *   - Skip credits missing <Amt>
 *   - ValDt as <Dt> and as <DtTm>
 *   - EndToEndId + RmtInf/Ustrd extraction don't blow up parse
 *   - Namespaced (urn:iso:std:iso:20022:...) AND bare XML both parse
 *   - Blank body → Error status with descriptive message
 *   - Malformed XML → Error status, exception is caught not rethrown
 *   - No-Ntry statement → Success + totalTransactions=0
 *   - Empty org → invoicesMatched=0, invoicesUpdated=0, no exception
 *   - null / empty request list guard
 *   - Bulk request list — multiple statements processed in one call
 *
 * Test assertions are cross-checked against Result.totalTransactions (parse
 * count) rather than the private parseCamt() output — that method is not
 * exposed, so we validate via the invocable entry point instead. This mirrors
 * the JiraTicketServiceTest pattern of asserting the public contract.
 *
 * Mock recording state is captured as INSTANCE fields on inner classes
 * (Apex forbids `static` inside inner classes; same convention as
 * JiraTicketServiceTest).
 */
@IsTest
private class SapPaymentReconciliationServiceTest {

    // ---------- CAMT.053 XML fixtures ----------

    // Standards-compliant single-credit statement with full envelope + iso20022 namespace.
    private static final String CAMT_SINGLE_CREDIT_NAMESPACED =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt>' +
            '<Stmt>' +
              '<Ntry>' +
                '<Amt Ccy="EUR">1449.00</Amt>' +
                '<CdtDbtInd>CRDT</CdtDbtInd>' +
                '<BookgDt><Dt>2026-06-15</Dt></BookgDt>' +
                '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
                '<NtryDtls>' +
                  '<TxDtls>' +
                    '<Refs><EndToEndId>DOC-000000012</EndToEndId></Refs>' +
                    '<RmtInf><Ustrd>Invoice DOC-000000012 payment</Ustrd></RmtInf>' +
                  '</TxDtls>' +
                '</NtryDtls>' +
              '</Ntry>' +
            '</Stmt>' +
          '</BkToCstmrStmt>' +
        '</Document>';

    // Same shape, no namespace — verifies Apex Dom.XmlNode.getName() returns local name.
    private static final String CAMT_SINGLE_CREDIT_BARE =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document>' +
          '<BkToCstmrStmt>' +
            '<Stmt>' +
              '<Ntry>' +
                '<Amt Ccy="EUR">1449.00</Amt>' +
                '<CdtDbtInd>CRDT</CdtDbtInd>' +
                '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
                '<NtryDtls>' +
                  '<TxDtls>' +
                    '<Refs><EndToEndId>DOC-000000012</EndToEndId></Refs>' +
                    '<RmtInf><Ustrd>Invoice DOC-000000012 payment</Ustrd></RmtInf>' +
                  '</TxDtls>' +
                '</NtryDtls>' +
              '</Ntry>' +
            '</Stmt>' +
          '</BkToCstmrStmt>' +
        '</Document>';

    // Two credits + one debit — debit must be filtered.
    private static final String CAMT_MIXED_CREDITS_AND_DEBIT =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt><Stmt>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">1200.00</Amt>' +
              '<CdtDbtInd>CRDT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>DOC-000000001</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">55.00</Amt>' +
              '<CdtDbtInd>DBIT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>SEPA-FEE</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">899.50</Amt>' +
              '<CdtDbtInd>CRDT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-16</Dt></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>DOC-000000002</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
          '</Stmt></BkToCstmrStmt>' +
        '</Document>';

    // All-debit statement — service should return 0 parsed transactions.
    private static final String CAMT_ALL_DEBITS =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt><Stmt>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">42.00</Amt>' +
              '<CdtDbtInd>DBIT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
            '</Ntry>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">17.99</Amt>' +
              '<CdtDbtInd>DBIT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
            '</Ntry>' +
          '</Stmt></BkToCstmrStmt>' +
        '</Document>';

    // Credit but no <Amt> element — must be skipped (parseCamt requires amount!=null).
    private static final String CAMT_CREDIT_WITHOUT_AMOUNT =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt><Stmt>' +
            '<Ntry>' +
              '<CdtDbtInd>CRDT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>DOC-BROKEN</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">100.00</Amt>' +
              '<CdtDbtInd>CRDT</CdtDbtInd>' +
              '<ValDt><Dt>2026-06-15</Dt></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>DOC-VALID</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
          '</Stmt></BkToCstmrStmt>' +
        '</Document>';

    // Value date as <DtTm> (ISO 8601 datetime) rather than plain <Dt>.
    private static final String CAMT_VALUE_DATE_AS_DTTM =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt><Stmt>' +
            '<Ntry>' +
              '<Amt Ccy="EUR">2500.00</Amt>' +
              '<CdtDbtInd>CRDT</CdtDbtInd>' +
              '<ValDt><DtTm>2026-06-15T14:23:11</DtTm></ValDt>' +
              '<NtryDtls><TxDtls><Refs><EndToEndId>DOC-DTTM</EndToEndId></Refs></TxDtls></NtryDtls>' +
            '</Ntry>' +
          '</Stmt></BkToCstmrStmt>' +
        '</Document>';

    // Empty statement — parseable, but no <Ntry>.
    private static final String CAMT_EMPTY_STATEMENT =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">' +
          '<BkToCstmrStmt><Stmt></Stmt></BkToCstmrStmt>' +
        '</Document>';

    // Well-formed enough to fail load() — mismatched tag.
    private static final String MALFORMED_XML =
        '<?xml version="1.0" encoding="UTF-8"?><Document><Broken></Wrong></Document>';

    // ---------- Helpers ----------

    private static SapPaymentReconciliationService.Request buildRequest(String xml) {
        SapPaymentReconciliationService.Request r = new SapPaymentReconciliationService.Request();
        r.camtXml = xml;
        r.source  = 'unit-test';
        return r;
    }

    private static SapPaymentReconciliationService.Result runSingle(String xml) {
        List<SapPaymentReconciliationService.Result> results =
            SapPaymentReconciliationService.reconcile(
                new List<SapPaymentReconciliationService.Request>{ buildRequest(xml) }
            );
        System.assertEquals(1, results.size(), 'One request → one result');
        return results[0];
    }

    // ---------- Tests: XML parse pipeline ----------

    @IsTest
    static void parseValidCamt053_singleCredit_extractsAmountCurrencyDate() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_NAMESPACED);

        System.assertEquals('Success', r.status,
            'Well-formed CAMT.053 with one credit must yield Success. Msg: ' + r.message);
        System.assertEquals(1, r.totalTransactions,
            'Exactly one CRDT entry with a decimal Amt must be parsed');
        System.assertEquals(0, r.invoicesMatched,
            'No Invoices exist in the org → no match possible');
        System.assertEquals(0, r.invoicesUpdated,
            'No matches → no updates');
        System.assert(r.message != null && r.message.contains('Parsed 1'),
            'Message must report parsed count. Got: ' + r.message);
    }

    @IsTest
    static void parseValidCamt053_multipleEntries_returnsAllCredits() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_MIXED_CREDITS_AND_DEBIT);

        System.assertEquals('Success', r.status);
        System.assertEquals(2, r.totalTransactions,
            'Two CRDT entries must be counted (the DBIT between them is filtered)');
    }

    @IsTest
    static void parseCamt053_ignoresDebits() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_ALL_DEBITS);

        System.assertEquals('Success', r.status,
            'All-debit statement is not an error — it just has nothing to reconcile');
        System.assertEquals(0, r.totalTransactions,
            'DBIT entries must be filtered out — money going out is not a receivable');
        System.assert(r.message != null && r.message.contains('No credit transactions'),
            'Empty-credit statement must be narrated as "nothing to reconcile". Got: ' + r.message);
    }

    @IsTest
    static void parseCamt053_creditWithoutAmount_isSkipped() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_CREDIT_WITHOUT_AMOUNT);

        System.assertEquals('Success', r.status,
            'Missing <Amt> on one Ntry should not error — parseEntry returns amount=null and it is filtered');
        System.assertEquals(1, r.totalTransactions,
            'Only the second Ntry (with Amt) counts; the amountless one is dropped');
    }

    @IsTest
    static void parseCamt053_valueDate_asDt_parsesSuccessfully() {
        // Covered by every valid fixture using <Dt> — assert again explicitly
        // so any regression to date parsing surfaces on this test.
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_NAMESPACED);
        System.assertEquals('Success', r.status,
            '<ValDt><Dt>YYYY-MM-DD</Dt></ValDt> must parse without throwing');
        System.assertEquals(1, r.totalTransactions);
    }

    @IsTest
    static void parseCamt053_valueDate_asDtTm_parsesSuccessfully() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_VALUE_DATE_AS_DTTM);
        System.assertEquals('Success', r.status,
            '<ValDt><DtTm>YYYY-MM-DDTHH:mm:ss</DtTm></ValDt> must parse without throwing');
        System.assertEquals(1, r.totalTransactions,
            'DtTm-based value date must not prevent the transaction from being counted');
    }

    @IsTest
    static void parseCamt053_endToEndId_isExtracted() {
        // We cannot directly observe endToEndId (parseCamt is private, CamtTransaction
        // returned only within the service), but we can confirm that a payload
        // rich with EndToEndId still parses cleanly and counts the transaction.
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_NAMESPACED);
        System.assertEquals('Success', r.status);
        System.assertEquals(1, r.totalTransactions,
            'EndToEndId extraction path must not raise. Match against DocumentNumber is TS-TEST-007.');
    }

    @IsTest
    static void parseCamt053_remittanceInfo_ustrd_isExtracted() {
        // Same rationale as EndToEndId: we assert the pipeline doesn't blow up
        // on RmtInf/Ustrd; end-to-end match against a real Invoice is TS-TEST-007.
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_NAMESPACED);
        System.assertEquals(1, r.totalTransactions,
            'RmtInf/Ustrd extraction path must not raise');
    }

    // ---------- Tests: namespace handling ----------

    @IsTest
    static void namespaceHandling_parsesXmlWithoutNamespace() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_BARE);
        System.assertEquals('Success', r.status,
            'Bare (no-namespace) XML must parse via Dom.XmlNode.getName() local-name lookup');
        System.assertEquals(1, r.totalTransactions,
            'Bare XML with 1 CRDT must yield 1 parsed transaction');
    }

    @IsTest
    static void namespaceHandling_parsesXmlWithNamespace() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_SINGLE_CREDIT_NAMESPACED);
        System.assertEquals('Success', r.status,
            'Namespaced (urn:iso:std:iso:20022:...) XML must parse identically to bare');
        System.assertEquals(1, r.totalTransactions,
            'Namespace prefix on <Document> must not hide <Ntry> children');
    }

    // ---------- Tests: error / edge branches ----------

    @IsTest
    static void reconcile_blankXml_returnsError() {
        SapPaymentReconciliationService.Result r = runSingle('');
        System.assertEquals('Error', r.status,
            'Blank camtXml must short-circuit as Error');
        System.assertEquals(0, r.totalTransactions,
            'No parse attempted → totalTransactions stays 0');
        System.assert(r.message != null && r.message.contains('Empty'),
            'Message must call out empty body. Got: ' + r.message);
    }

    @IsTest
    static void parseCamt053_malformedXml_isCaughtNotThrown() {
        SapPaymentReconciliationService.Result r = runSingle(MALFORMED_XML);
        System.assertEquals('Error', r.status,
            'Dom.Document.load() failure must be caught and mapped to Error, not rethrown');
        System.assert(r.message != null && r.message.startsWith('CAMT parse failure:'),
            'Error message must start with "CAMT parse failure:" to aid ops triage. Got: ' + r.message);
        System.assertEquals(0, r.totalTransactions,
            'Parse never reached txns.size() → totalTransactions stays at initial 0');
    }

    @IsTest
    static void parseCamt053_emptyStatement_noNtry_returnsSuccess() {
        SapPaymentReconciliationService.Result r = runSingle(CAMT_EMPTY_STATEMENT);
        System.assertEquals('Success', r.status,
            'Statement with no <Ntry> must still be Success — the bank had no activity that day');
        System.assertEquals(0, r.totalTransactions);
        System.assert(r.message != null && r.message.contains('No credit transactions'),
            'Should narrate the no-op. Got: ' + r.message);
    }

    // ---------- Tests: match/reconcile behavior with empty org ----------

    @IsTest
    static void reconcile_emptyOrg_noMatchesReturned() {
        // TS-TEST-007 blocks Invoice DML → we can only prove the negative:
        // with 0 Invoices in the org, even a well-formed CRDT with a matching
        // DocumentNumber pattern must resolve to 0 matches, 0 updates, no error.
        SapPaymentReconciliationService.Result r = runSingle(CAMT_MIXED_CREDITS_AND_DEBIT);

        System.assertEquals('Success', r.status,
            'Empty-org reconcile must not throw — the "no candidate invoices" branch is legitimate');
        System.assertEquals(2, r.totalTransactions,
            'Parse should still succeed and count both CRDT entries');
        System.assertEquals(0, r.invoicesMatched,
            'Zero open Invoices → zero matches by definition');
        System.assertEquals(0, r.invoicesUpdated,
            'No matches → no Database.update calls attempted');
    }

    // ---------- Tests: bulk + input-guard ----------

    @IsTest
    static void reconcile_bulk_multipleStatements_processedIndependently() {
        List<SapPaymentReconciliationService.Request> reqs =
            new List<SapPaymentReconciliationService.Request>{
                buildRequest(CAMT_SINGLE_CREDIT_NAMESPACED),
                buildRequest(CAMT_MIXED_CREDITS_AND_DEBIT),
                buildRequest(CAMT_ALL_DEBITS),
                buildRequest(''),          // blank → Error
                buildRequest(MALFORMED_XML) // parse failure → Error
            };

        Test.startTest();
        List<SapPaymentReconciliationService.Result> results =
            SapPaymentReconciliationService.reconcile(reqs);
        Test.stopTest();

        System.assertEquals(5, results.size(),
            'Bulk 5 requests must yield 5 results, one per input');
        System.assertEquals('Success', results[0].status);
        System.assertEquals(1, results[0].totalTransactions);
        System.assertEquals('Success', results[1].status);
        System.assertEquals(2, results[1].totalTransactions);
        System.assertEquals('Success', results[2].status);
        System.assertEquals(0, results[2].totalTransactions);
        System.assertEquals('Error', results[3].status,
            'Blank body → Error');
        System.assertEquals('Error', results[4].status,
            'Malformed XML → Error');
    }

    @IsTest
    static void reconcile_nullAndEmptyRequestList_returnEmpty() {
        Test.startTest();
        List<SapPaymentReconciliationService.Result> resNull =
            SapPaymentReconciliationService.reconcile(null);
        List<SapPaymentReconciliationService.Result> resEmpty =
            SapPaymentReconciliationService.reconcile(
                new List<SapPaymentReconciliationService.Request>()
            );
        Test.stopTest();

        System.assertEquals(0, resNull.size(),
            'null request list must return an empty results list, not NPE');
        System.assertEquals(0, resEmpty.size(),
            'empty request list must return an empty results list');
    }
}
