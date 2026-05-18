/**
 * SAP Tax Determination Service — parallel adapter alongside the native
 * commercetax.TaxEngineAdapter chain that runs at Invoice generation.
 *
 * Two-tier resolution (ADR-024):
 *   1. Try SAP S/4HANA API_DETERMINE_TAX_SRV — the production-target endpoint.
 *   2. If sandbox returns 403 (license-gated trial) or any error, fall back to
 *      a deterministic country-based rate table. Captures the realistic
 *      DACH + Western EU rates (DE 19 / AT 20 / CH 7.7 / NL 21 / FR 20).
 *
 * The result is written to Invoice.SAP_Tax_Amount__c + SAP_Tax_Rate__c +
 * SAP_Tax_Calculated_At__c + Tax_Engine_Used__c so the production-readiness
 * audit shows two parallel readings: the native commercetax chain (already on
 * Invoice line items) AND the SAP path. Recruiters / auditors can compare.
 *
 * NOT a replacement for the existing tax engine — coexists with it. Production
 * decision (per ADR-015): tax authority migrates fully to SAP FI/SD when the
 * full SAP license is procured. This service is the path the migration runs on.
 */
public with sharing class SapTaxCalculationService {

    public class Request {
        @InvocableVariable(required=true label='Invoice Id')
        public Id invoiceId;
    }

    public class Result {
        @InvocableVariable(label='Invoice Id')
        public Id invoiceId;
        @InvocableVariable(label='Tax Rate (percent)')
        public Decimal taxRate;
        @InvocableVariable(label='Tax Amount')
        public Decimal taxAmount;
        @InvocableVariable(label='Engine Used')
        public String engineUsed;     // SAP_API | SAP_FALLBACK_TABLE
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    // Country → standard VAT rate fallback table. DACH-first; expanded to common Western EU.
    private static final Map<String, Decimal> FALLBACK_RATES = new Map<String, Decimal>{
        'DE' => 19.00,    'GERMANY' => 19.00,
        'AT' => 20.00,    'AUSTRIA' => 20.00,
        'CH' => 7.70,     'SWITZERLAND' => 7.70,
        'NL' => 21.00,    'NETHERLANDS' => 21.00,
        'FR' => 20.00,    'FRANCE' => 20.00,
        'IT' => 22.00,    'ITALY' => 22.00,
        'ES' => 21.00,    'SPAIN' => 21.00,
        'BE' => 21.00,    'BELGIUM' => 21.00,
        'GB' => 20.00,    'UK' => 20.00,    'UNITED KINGDOM' => 20.00,
        'US' => 0.00,     'USA' => 0.00     // US sales tax is per-state; SAP would resolve via tax jurisdiction code
    };
    private static final Decimal DEFAULT_RATE = 19.00;  // Demo defaults to Germany if country unknown

    @InvocableMethod(label='Calculate Tax via SAP for Invoice' description='Two-tier: tries SAP S/4HANA tax API first; falls back to country-based rate table if SAP is unavailable. Writes results to SAP_Tax_* fields on the Invoice.')
    public static List<Result> calculateForInvoice(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.API_Base_URL__c) || String.isBlank(cfg.API_Key__c)) {
            for (Request r : requests) {
                Result res = new Result();
                res.invoiceId = r.invoiceId;
                res.status = 'Error';
                res.message = 'SAP_Config__c missing or incomplete.';
                results.add(res);
            }
            return results;
        }

        Set<Id> invoiceIds = new Set<Id>();
        for (Request r : requests) if (r.invoiceId != null) invoiceIds.add(r.invoiceId);
        if (invoiceIds.isEmpty()) return results;

        Map<Id, Invoice> invoiceMap = new Map<Id, Invoice>([
            SELECT Id, DocumentNumber, BillingAccount.Name, BillingAccount.BillingCountry,
                   TotalAmount, TotalTaxAmount
            FROM Invoice
            WHERE Id IN :invoiceIds
        ]);

        String baseUrl = cfg.API_Base_URL__c;
        if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;
        Datetime now = System.now();
        List<Invoice> updates = new List<Invoice>();

        for (Request r : requests) {
            Result res = new Result();
            res.invoiceId = r.invoiceId;
            Invoice inv = invoiceMap.get(r.invoiceId);
            if (inv == null) {
                res.status = 'Error';
                res.message = 'Invoice not found: ' + r.invoiceId;
                results.add(res);
                continue;
            }

            String country = (inv.BillingAccount != null) ? inv.BillingAccount.BillingCountry : null;
            Decimal taxableAmount = (inv.TotalAmount == null) ? 0 : inv.TotalAmount;

            // Tier 1: try real SAP tax endpoint.
            Decimal rate = null;
            String engineUsed = null;
            try {
                rate = trySapTaxApi(baseUrl, cfg.API_Key__c, country, taxableAmount);
                if (rate != null) engineUsed = 'SAP_API';
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'SAP tax API call failed (will fallback): ' + e.getMessage());
            }

            // Tier 2: country-based fallback table.
            if (rate == null) {
                rate = resolveFallbackRate(country);
                engineUsed = 'SAP_FALLBACK_TABLE';
            }

            Decimal taxAmount = (taxableAmount * rate / 100).setScale(2);
            res.taxRate = rate;
            res.taxAmount = taxAmount;
            res.engineUsed = engineUsed;
            res.status = 'Success';
            res.message = 'Tax calculated via ' + engineUsed + ': ' + rate + '% on amount ' + taxableAmount + ' = ' + taxAmount;

            updates.add(new Invoice(
                Id = inv.Id,
                SAP_Tax_Rate__c = rate,
                SAP_Tax_Amount__c = taxAmount,
                SAP_Tax_Calculated_At__c = now,
                Tax_Engine_Used__c = engineUsed
            ));
            results.add(res);
        }

        if (!updates.isEmpty()) {
            try {
                update updates;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to write SAP tax fields back to Invoice(s): ' + e.getMessage());
            }
        }
        return results;
    }

    private static Decimal trySapTaxApi(String baseUrl, String apiKey, String country, Decimal amount) {
        // Production-target endpoint. SAP API Hub sandbox 403s this; full S/4HANA license unlocks.
        String endpoint = baseUrl + '/s4hanacloud/sap/opu/odata/sap/API_DETERMINE_TAX_SRV/Tax';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('APIKey', apiKey);
        req.setHeader('Accept', 'application/json');
        req.setHeader('Accept-Encoding', 'identity');
        req.setTimeout(15000);

        HttpResponse resp = new Http().send(req);
        Integer status = resp.getStatusCode();
        if (status == 200) {
            // Parse rate from response — schema varies per SAP module version, this is a sketch:
            // expected shape: { d: { results: [ { TaxRate: 19.0, TaxJurisdictionCode: 'DE' } ] } }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            Object d = body.get('d');
            if (d instanceof Map<String, Object>) {
                Object rs = ((Map<String, Object>) d).get('results');
                if (rs instanceof List<Object>) {
                    List<Object> rows = (List<Object>) rs;
                    if (!rows.isEmpty() && rows[0] instanceof Map<String, Object>) {
                        Object rateVal = ((Map<String, Object>) rows[0]).get('TaxRate');
                        if (rateVal != null) return Decimal.valueOf(String.valueOf(rateVal));
                    }
                }
            }
        }
        // 403 / 404 / other: signal "fallback needed" by returning null
        return null;
    }

    @TestVisible
    private static Decimal resolveFallbackRate(String country) {
        if (String.isBlank(country)) return DEFAULT_RATE;
        String key = country.toUpperCase().trim();
        return FALLBACK_RATES.containsKey(key) ? FALLBACK_RATES.get(key) : DEFAULT_RATE;
    }
}
