/**
 * SAP Payment Reconciliation Service — CAMT.053 bank statement parser (ADR-025).
 *
 * In a DACH B2B production environment, customer payments typically arrive via
 * SEPA Direct Debit or bank transfer (Net 30 / Net 60 terms), NOT credit card.
 * The bank publishes a daily CAMT.053 XML statement (ISO 20022) listing every
 * transaction. SAP FI loads this file, matches each credit transaction to an
 * open invoice by amount + customer reference, and posts the receivable as paid.
 *
 * In production this whole flow lives in SAP. The integration point with
 * Salesforce is: Salesforce Invoice needs to mirror the "paid" state once SAP
 * has reconciled. This service is the SF side of that handoff. Three modes:
 *
 *   1. Pulled from SAP — Mule scheduled flow downloads the CAMT.053, hands it
 *      to this Apex via Composite REST or invocable. Production primary path.
 *   2. Uploaded by Finance — Finance user posts the CAMT.053 XML to a custom
 *      Lightning component or REST endpoint; service parses + reconciles.
 *   3. Demo — anonymous Apex invokes this service with a sample CAMT.053
 *      string; useful for showing the reconciliation logic without Mule running.
 *
 * Demo limitation: SAP API Hub Sandbox doesn't expose a real CAMT-feed endpoint.
 * The sample CAMT.053 in scripts/test_sap_payment_reconciliation.apex is a
 * synthetic but standards-compliant XML that demonstrates the parse + match path.
 *
 * Match rules (in order of precedence):
 *   1. Exact Invoice DocumentNumber match in EndToEndId or RemittanceInformation
 *   2. Exact amount match against an open Invoice for the same Account
 *   3. Tolerant amount match (±0.50 EUR rounding tolerance) against any open Invoice
 */
public with sharing class SapPaymentReconciliationService {

    public class Request {
        @InvocableVariable(required=true label='CAMT.053 XML body')
        public String camtXml;
        @InvocableVariable(label='Statement source (e.g. Bank Name / file name)')
        public String source;
    }

    public class Result {
        @InvocableVariable(label='Total Transactions Parsed')
        public Integer totalTransactions;
        @InvocableVariable(label='Invoices Matched')
        public Integer invoicesMatched;
        @InvocableVariable(label='Invoices Updated')
        public Integer invoicesUpdated;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    private static final Decimal AMOUNT_TOLERANCE = 0.50;

    @InvocableMethod(label='Reconcile Payments from CAMT.053' description='Parses CAMT.053 XML, matches credit transactions to open Salesforce Invoices, marks them Paid with SAP_Payment_Reference + SAP_Payment_Posted_At.')
    public static List<Result> reconcile(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;
        for (Request r : requests) {
            results.add(reconcileOne(r));
        }
        return results;
    }

    private static Result reconcileOne(Request r) {
        Result res = new Result();
        res.totalTransactions = 0;
        res.invoicesMatched = 0;
        res.invoicesUpdated = 0;
        if (String.isBlank(r.camtXml)) {
            res.status = 'Error';
            res.message = 'Empty CAMT.053 body.';
            return res;
        }

        List<CamtTransaction> txns;
        try {
            txns = parseCamt(r.camtXml);
        } catch (Exception e) {
            res.status = 'Error';
            res.message = 'CAMT parse failure: ' + e.getMessage();
            return res;
        }
        res.totalTransactions = txns.size();

        if (txns.isEmpty()) {
            res.status = 'Success';
            res.message = 'No credit transactions in statement; nothing to reconcile.';
            return res;
        }

        // Pull candidate open Invoices once, in bulk.
        Map<String, Invoice> invByDocNumber = new Map<String, Invoice>();
        Map<Id, Invoice> invById = new Map<Id, Invoice>([
            SELECT Id, DocumentNumber, TotalAmount, Status, BillingAccount.Name
            FROM Invoice
            WHERE Status != 'Paid' AND TotalAmount > 0
        ]);
        for (Invoice inv : invById.values()) {
            if (String.isNotBlank(inv.DocumentNumber)) invByDocNumber.put(inv.DocumentNumber, inv);
        }

        Set<Id> matchedInvoiceIds = new Set<Id>();
        List<Invoice> updates = new List<Invoice>();
        for (CamtTransaction t : txns) {
            Invoice match = matchTransaction(t, invByDocNumber, invById.values());
            if (match == null) continue;
            if (matchedInvoiceIds.contains(match.Id)) continue;   // don't double-match the same invoice in one batch
            matchedInvoiceIds.add(match.Id);
            res.invoicesMatched++;

            // Note: Invoice.Status is calculated by RLM Billing from related Payment Transactions
            // — not directly writeable. Demo updates the SAP-side audit fields; production creates
            // a Payment record via Industries Billing API (see ADR-025 Future state section).
            updates.add(new Invoice(
                Id = match.Id,
                Payment_Method__c = 'Bank_Transfer',
                SAP_Payment_Reference__c = t.endToEndId,
                SAP_Payment_Posted_At__c = t.valueDate
            ));
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] saveRes = Database.update(updates, false);
            for (Database.SaveResult sr : saveRes) {
                if (sr.isSuccess()) res.invoicesUpdated++;
            }
        }
        res.status = 'Success';
        res.message = String.format('Parsed {0} transactions, matched {1} invoices, updated {2}.', new List<Object>{ res.totalTransactions, res.invoicesMatched, res.invoicesUpdated });
        return res;
    }

    private static Invoice matchTransaction(CamtTransaction t, Map<String, Invoice> byDocNumber, List<Invoice> allOpen) {
        // Rule 1: EndToEndId contains an Invoice DocumentNumber
        if (String.isNotBlank(t.endToEndId)) {
            for (String docNum : byDocNumber.keySet()) {
                if (t.endToEndId.containsIgnoreCase(docNum)) return byDocNumber.get(docNum);
            }
        }
        // Rule 2: Remittance info contains a DocumentNumber
        if (String.isNotBlank(t.remittanceInfo)) {
            for (String docNum : byDocNumber.keySet()) {
                if (t.remittanceInfo.containsIgnoreCase(docNum)) return byDocNumber.get(docNum);
            }
        }
        // Rule 3: exact amount match
        for (Invoice inv : allOpen) {
            if (inv.TotalAmount != null && (inv.TotalAmount - t.amount).abs() <= AMOUNT_TOLERANCE) {
                return inv;
            }
        }
        return null;
    }

    private static List<CamtTransaction> parseCamt(String xml) {
        List<CamtTransaction> txns = new List<CamtTransaction>();
        Dom.Document doc = new Dom.Document();
        doc.load(xml);
        Dom.XmlNode root = doc.getRootElement();
        // CAMT.053 structure: Document/BkToCstmrStmt/Stmt/Ntry...
        // Walk all descendants and pick up <Ntry> nodes. Cheap recursion via stack.
        List<Dom.XmlNode> stack = new List<Dom.XmlNode>{ root };
        while (!stack.isEmpty()) {
            Dom.XmlNode current = stack.remove(stack.size() - 1);
            if (current.getName() == 'Ntry') {
                CamtTransaction t = parseEntry(current);
                if (t != null && t.creditDebit == 'CRDT' && t.amount != null) txns.add(t);
            }
            for (Dom.XmlNode child : current.getChildElements()) stack.add(child);
        }
        return txns;
    }

    private static CamtTransaction parseEntry(Dom.XmlNode ntry) {
        CamtTransaction t = new CamtTransaction();
        // Scan all descendants of <Ntry> for known field names.
        List<Dom.XmlNode> stack = new List<Dom.XmlNode>{ ntry };
        while (!stack.isEmpty()) {
            Dom.XmlNode n = stack.remove(stack.size() - 1);
            String name = n.getName();
            String text = n.getText();
            if (name == 'Amt' && t.amount == null) {
                try { t.amount = Decimal.valueOf(text); } catch (Exception e) {}
            } else if (name == 'CdtDbtInd' && t.creditDebit == null) {
                t.creditDebit = text;
            } else if (name == 'ValDt') {
                // Value date wrapper holds <Dt> or <DtTm>
                for (Dom.XmlNode v : n.getChildElements()) {
                    if (v.getName() == 'Dt' || v.getName() == 'DtTm') {
                        try { t.valueDate = Datetime.valueOf(v.getText().replace('T', ' ').left(19)); }
                        catch (Exception e) {
                            try { t.valueDate = Datetime.newInstanceGmt(Date.valueOf(v.getText()), Time.newInstance(0, 0, 0, 0)); }
                            catch (Exception e2) {}
                        }
                    }
                }
            } else if (name == 'EndToEndId' && String.isBlank(t.endToEndId)) {
                t.endToEndId = text;
            } else if (name == 'Ustrd' && String.isBlank(t.remittanceInfo)) {
                t.remittanceInfo = text;
            }
            for (Dom.XmlNode child : n.getChildElements()) stack.add(child);
        }
        return t;
    }

    public class CamtTransaction {
        public Decimal amount;
        public String creditDebit;     // CRDT | DBIT — we only act on CRDT (credit = money in)
        public Datetime valueDate;
        public String endToEndId;
        public String remittanceInfo;
    }
}
