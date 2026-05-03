/**
 * Salesforce Revenue Cloud Tax Engine Adapter — TechnoStore demo.
 *
 * Implements commercetax.TaxEngineAdapter to satisfy the SF Tax Engine
 * provider contract. Computes a flat 19% German VAT on every taxable line
 * item, no external callout required. Suitable for demo use only — real
 * production would route to Avalara / Vertex / native tax tables.
 */
global with sharing class TechnoStoreTaxEngineAdapter implements commercetax.TaxEngineAdapter {

    private static final Double VAT_RATE = 0.19;
    private static final String TAX_CODE = 'VAT_19_DE';
    private static final String TAX_ID = 'DE_VAT_19';

    global commercetax.TaxEngineResponse processRequest(commercetax.TaxEngineContext context) {
        commercetax.TaxEngineRequest engineReq = context.getRequest();
        return buildCalculateTaxResponse(engineReq);
    }

    private commercetax.CalculateTaxResponse buildCalculateTaxResponse(commercetax.TaxEngineRequest engineReq) {
        commercetax.CalculateTaxResponse calcResp = new commercetax.CalculateTaxResponse();
        calcResp.setTaxType(commercetax.CalculateTaxType.ACTUAL);
        calcResp.setTaxTransactionType(commercetax.TaxTransactionType.DEBIT);
        calcResp.setStatus(commercetax.TaxTransactionStatus.UNCOMMITTED);
        calcResp.setEffectiveDate(System.now());
        calcResp.setTransactionDate(System.now());
        calcResp.setStatusDescription('Calculated by TechnoStoreTaxEngineAdapter');

        List<commercetax.TaxLineItemRequest> reqLines = extractLineItems(engineReq);
        List<commercetax.LineItemResponse> respLines = new List<commercetax.LineItemResponse>();
        Double totalTax = 0;
        Double totalAmount = 0;

        for (commercetax.TaxLineItemRequest li : reqLines) {
            Double amount = (li.amount != null) ? li.amount : 0;
            Double tax = ((Decimal.valueOf(amount) * Decimal.valueOf(VAT_RATE)).setScale(2)).doubleValue();

            commercetax.LineItemResponse lineResp = new commercetax.LineItemResponse();
            lineResp.setLineNumber(li.lineNumber);
            lineResp.setProductCode(li.productCode);
            lineResp.setQuantity(li.quantity);
            lineResp.setIsTaxable(true);
            lineResp.setTaxCode(TAX_CODE);
            lineResp.setEffectiveDate(System.now());

            commercetax.TaxDetailsResponse taxDetails = new commercetax.TaxDetailsResponse();
            taxDetails.setRate(VAT_RATE);
            taxDetails.setTax(tax);
            taxDetails.setTaxableAmount(amount);
            taxDetails.setTaxId(TAX_ID);
            lineResp.setTaxes(new List<commercetax.TaxDetailsResponse>{ taxDetails });

            commercetax.AmountDetailsResponse lineAmounts = new commercetax.AmountDetailsResponse();
            lineAmounts.setTaxAmount(tax);
            lineAmounts.setTotalAmount(amount);
            lineAmounts.setTotalAmountWithTax(amount + tax);
            lineResp.setAmountDetails(lineAmounts);

            respLines.add(lineResp);
            totalTax += tax;
            totalAmount += amount;
        }

        calcResp.setLineItems(respLines);

        commercetax.AmountDetailsResponse headerAmounts = new commercetax.AmountDetailsResponse();
        headerAmounts.setTaxAmount(totalTax);
        headerAmounts.setTotalAmount(totalAmount);
        headerAmounts.setTotalAmountWithTax(totalAmount + totalTax);
        calcResp.setAmountDetails(headerAmounts);

        return calcResp;
    }

    private List<commercetax.TaxLineItemRequest> extractLineItems(commercetax.TaxEngineRequest engineReq) {
        List<commercetax.TaxLineItemRequest> result = new List<commercetax.TaxLineItemRequest>();
        try {
            commercetax.TaxTransactionRequest trxReq = (commercetax.TaxTransactionRequest) engineReq;
            if (trxReq != null && trxReq.lineItems != null) {
                result = trxReq.lineItems;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'TechnoStoreTaxEngineAdapter: could not cast request to TaxTransactionRequest: ' + e.getMessage());
        }
        return result;
    }
}
