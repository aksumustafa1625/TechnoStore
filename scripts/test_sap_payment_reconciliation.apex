// Phase 4 end-to-end test. Synthesise a CAMT.053 XML that includes:
//  - One credit entry that matches an open Invoice DocumentNumber via EndToEndId
//  - One credit entry that matches by amount only
//  - One debit entry (should be ignored — money out, not customer payment)

// Pick two open Invoices to target.
List<Invoice> open = [SELECT Id, DocumentNumber, TotalAmount, Status FROM Invoice WHERE Status != 'Paid' AND TotalAmount > 0 ORDER BY CreatedDate DESC LIMIT 2];
if (open.size() < 2) {
    System.debug('Need at least 2 open invoices to demo both match rules. Found: ' + open.size());
    return;
}
Invoice docMatch = open[0];
Invoice amtMatch = open[1];
System.debug('Targeting:');
System.debug('  EndToEndId match: ' + docMatch.DocumentNumber + ' (Total=' + docMatch.TotalAmount + ')');
System.debug('  Amount-only match: ' + amtMatch.DocumentNumber + ' (Total=' + amtMatch.TotalAmount + ')');

// Build the CAMT.053 XML. ISO 20022 spec compliant, minimal.
String camt =
'<?xml version="1.0" encoding="UTF-8"?>'
+ '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">'
+ '<BkToCstmrStmt><Stmt>'
+ '<Id>DEMO-STMT-001</Id>'
// Entry 1: matches by EndToEndId (carries the SF DocumentNumber)
+ '<Ntry>'
+   '<Amt Ccy="EUR">' + docMatch.TotalAmount + '</Amt>'
+   '<CdtDbtInd>CRDT</CdtDbtInd>'
+   '<ValDt><Dt>2026-05-18</Dt></ValDt>'
+   '<NtryDtls><TxDtls>'
+     '<Refs><EndToEndId>INV-' + docMatch.DocumentNumber + '-PAYMENT</EndToEndId></Refs>'
+     '<RmtInf><Ustrd>Customer payment for ' + docMatch.DocumentNumber + '</Ustrd></RmtInf>'
+   '</TxDtls></NtryDtls>'
+ '</Ntry>'
// Entry 2: matches by amount only
+ '<Ntry>'
+   '<Amt Ccy="EUR">' + amtMatch.TotalAmount + '</Amt>'
+   '<CdtDbtInd>CRDT</CdtDbtInd>'
+   '<ValDt><Dt>2026-05-18</Dt></ValDt>'
+   '<NtryDtls><TxDtls>'
+     '<Refs><EndToEndId>UNRELATED-REF-12345</EndToEndId></Refs>'
+   '</TxDtls></NtryDtls>'
+ '</Ntry>'
// Entry 3: debit — should be ignored
+ '<Ntry>'
+   '<Amt Ccy="EUR">100.00</Amt>'
+   '<CdtDbtInd>DBIT</CdtDbtInd>'
+   '<ValDt><Dt>2026-05-18</Dt></ValDt>'
+ '</Ntry>'
+ '</Stmt></BkToCstmrStmt></Document>';

SapPaymentReconciliationService.Request req = new SapPaymentReconciliationService.Request();
req.camtXml = camt;
req.source = 'Demo CAMT.053 — anonymous Apex';

List<SapPaymentReconciliationService.Result> results = SapPaymentReconciliationService.reconcile(new List<SapPaymentReconciliationService.Request>{ req });
for (SapPaymentReconciliationService.Result r : results) {
    System.debug('=== Reconciliation Result ===');
    System.debug('  totalTransactions = ' + r.totalTransactions);
    System.debug('  invoicesMatched   = ' + r.invoicesMatched);
    System.debug('  invoicesUpdated   = ' + r.invoicesUpdated);
    System.debug('  status            = ' + r.status);
    System.debug('  message           = ' + r.message);
}

System.debug('=== Invoices after reconciliation ===');
for (Invoice inv : [SELECT DocumentNumber, Status, Payment_Method__c, SAP_Payment_Reference__c, SAP_Payment_Posted_At__c FROM Invoice WHERE Id IN (:docMatch.Id, :amtMatch.Id)]) {
    System.debug('  ' + inv.DocumentNumber + ' Status=' + inv.Status + ' Method=' + inv.Payment_Method__c + ' Ref=' + inv.SAP_Payment_Reference__c + ' PostedAt=' + inv.SAP_Payment_Posted_At__c);
}
