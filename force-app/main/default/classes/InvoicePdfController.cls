public with sharing class InvoicePdfController {

    public Invoice invoice { get; set; }
    public List<InvoiceLineWrapper> lineWrappers { get; set; }

    public InvoicePdfController() {
        Id invoiceId = ApexPages.currentPage().getParameters().get('id');
        if (invoiceId != null) {
            loadData(invoiceId);
        }
        if (lineWrappers == null) {
            lineWrappers = new List<InvoiceLineWrapper>();
        }
    }

    private void loadData(Id invoiceId) {
        List<Invoice> results = [
            SELECT Id, DocumentNumber, InvoiceDate, DueDate,
                   TotalAmount, TotalAmountWithTax, TotalTaxAmount,
                   Status, Stripe_Payment_Status__c, Paid_Date__c,
                   Has_Physical__c, Has_Digital__c,
                   BillingAccountId, BillToContactId,
                   BillingAccount.Name, BillingAccount.BillingStreet,
                   BillingAccount.BillingCity, BillingAccount.BillingState,
                   BillingAccount.BillingPostalCode, BillingAccount.BillingCountry,
                   BillToContact.Name, BillToContact.Email
            FROM Invoice WHERE Id = :invoiceId LIMIT 1
        ];
        if (results.isEmpty()) return;
        invoice = results[0];

        List<InvoiceLine> lines = [
            SELECT Id, Product2.Name,
                   Quantity, UnitPrice, ChargeAmount, TaxAmount, LineAmount,
                   InvoiceLineStartDate, InvoiceLineEndDate
            FROM InvoiceLine WHERE InvoiceId = :invoiceId
            ORDER BY CreatedDate ASC
        ];

        lineWrappers = new List<InvoiceLineWrapper>();
        for (InvoiceLine line : lines) {
            lineWrappers.add(new InvoiceLineWrapper(line));
        }
    }

    public String getIssueDate() {
        return (invoice == null || invoice.InvoiceDate == null) ? '' : invoice.InvoiceDate.format();
    }

    public String getDueDateStr() {
        return (invoice == null || invoice.DueDate == null) ? '' : invoice.DueDate.format();
    }

    public String getPaidDateStr() {
        return (invoice == null || invoice.Paid_Date__c == null) ? '—' : invoice.Paid_Date__c.format();
    }

    public Decimal getTotalAmount() {
        if (invoice == null) return 0;
        if (invoice.TotalAmountWithTax != null) return invoice.TotalAmountWithTax;
        if (invoice.TotalAmount != null) return invoice.TotalAmount;
        return 0;
    }

    public Decimal getTaxAmount() {
        return (invoice == null || invoice.TotalTaxAmount == null) ? 0 : invoice.TotalTaxAmount;
    }

    public Decimal getSubtotalAmount() {
        return getTotalAmount() - getTaxAmount();
    }

    public String getTotalFormatted() { return formatCurrency(getTotalAmount()); }
    public String getTaxFormatted() { return formatCurrency(getTaxAmount()); }
    public String getSubtotalFormatted() { return formatCurrency(getSubtotalAmount()); }

    public String getPaymentStatusLabel() {
        if (invoice == null) return 'DRAFT';
        String s = invoice.Stripe_Payment_Status__c;
        if (s == 'Paid') return 'PAID';
        if (s == 'Sent') return 'AWAITING PAYMENT';
        if (s == 'Failed') return 'PAYMENT FAILED';
        return 'DRAFT';
    }

    public String getPaymentStatusKey() {
        if (invoice == null) return 'draft';
        String s = invoice.Stripe_Payment_Status__c;
        if (s == 'Paid') return 'paid';
        if (s == 'Sent') return 'pending';
        if (s == 'Failed') return 'failed';
        return 'draft';
    }

    public String getFulfillmentLabel() {
        if (invoice == null) return 'Standard Order';
        Boolean p = invoice.Has_Physical__c == true;
        Boolean d = invoice.Has_Digital__c == true;
        if (p && d) return 'Hardware + SaaS Bundle';
        if (p) return 'Hardware Shipment';
        if (d) return 'Digital / SaaS License';
        return 'Standard Order';
    }

    public Boolean getIsPaid() {
        return invoice != null && invoice.Stripe_Payment_Status__c == 'Paid';
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) return '$0.00';
        return '$' + amount.setScale(2).format();
    }

    public class InvoiceLineWrapper {
        public InvoiceLine line { get; set; }
        public String productName { get; set; }
        public String periodStr { get; set; }
        public String quantityStr { get; set; }
        public String unitPriceFormatted { get; set; }
        public String taxFormatted { get; set; }
        public String lineTotalFormatted { get; set; }

        public InvoiceLineWrapper(InvoiceLine l) {
            line = l;
            productName = (l.Product2 != null && l.Product2.Name != null) ? l.Product2.Name : 'Service';

            if (l.InvoiceLineStartDate != null && l.InvoiceLineEndDate != null) {
                periodStr = l.InvoiceLineStartDate.format() + ' — ' + l.InvoiceLineEndDate.format();
            } else {
                periodStr = '—';
            }

            quantityStr = (l.Quantity == null) ? '—' : l.Quantity.setScale(0).format();

            Decimal up = (l.UnitPrice == null) ? 0 : l.UnitPrice;
            Decimal tax = (l.TaxAmount == null) ? 0 : l.TaxAmount;
            Decimal lineAmt = (l.LineAmount != null) ? l.LineAmount : ((l.ChargeAmount == null ? 0 : l.ChargeAmount) + tax);

            unitPriceFormatted = formatCurrency(up);
            taxFormatted = formatCurrency(tax);
            lineTotalFormatted = formatCurrency(lineAmt);
        }
    }
}
