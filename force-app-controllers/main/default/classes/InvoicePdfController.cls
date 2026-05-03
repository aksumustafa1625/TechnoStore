public with sharing class InvoicePdfController {

    private static final Decimal VAT_RATE = 0.19;

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
                   Status, Stripe_Payment_Status__c, Stripe_Payment_URL__c, Paid_Date__c,
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

        Map<Id, OrderItem> orderItemByProduct = buildOrderItemMap(invoice.BillingAccountId);

        List<InvoiceLine> lines = [
            SELECT Id, Product2Id, Product2.Name,
                   Quantity, UnitPrice, ChargeAmount, TaxAmount, LineAmount,
                   InvoiceLineStartDate, InvoiceLineEndDate
            FROM InvoiceLine WHERE InvoiceId = :invoiceId
            ORDER BY CreatedDate ASC
        ];

        lineWrappers = new List<InvoiceLineWrapper>();
        for (InvoiceLine line : lines) {
            OrderItem matchedOi = (line.Product2Id != null) ? orderItemByProduct.get(line.Product2Id) : null;
            lineWrappers.add(new InvoiceLineWrapper(line, matchedOi));
        }
    }

    private static Map<Id, OrderItem> buildOrderItemMap(Id accountId) {
        Map<Id, OrderItem> result = new Map<Id, OrderItem>();
        if (accountId == null) return result;
        List<Order> orders = [
            SELECT Id FROM Order
            WHERE AccountId = :accountId AND Status = 'Activated'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (orders.isEmpty()) return result;
        for (OrderItem oi : [
            SELECT Id, Product2Id, ListPrice, UnitPrice, Quantity, TotalPrice
            FROM OrderItem WHERE OrderId = :orders[0].Id
        ]) {
            if (oi.Product2Id != null) result.put(oi.Product2Id, oi);
        }
        return result;
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

    public Decimal getSubtotalAmount() {
        Decimal total = getTotalAmount();
        return (total == 0) ? 0 : (total / (1 + VAT_RATE)).setScale(2);
    }

    public Decimal getTaxAmount() {
        return (getTotalAmount() - getSubtotalAmount()).setScale(2);
    }

    public String getTotalFormatted() { return formatCurrency(getTotalAmount()); }
    public String getTaxFormatted() { return formatCurrency(getTaxAmount()); }
    public String getSubtotalFormatted() { return formatCurrency(getSubtotalAmount()); }

    public String getVatLabel() {
        return 'VAT (' + (VAT_RATE * 100).setScale(0).format() + '%)';
    }

    public Boolean getPaidOverride() {
        String paidParam = ApexPages.currentPage().getParameters().get('paid');
        return paidParam != null && paidParam.equalsIgnoreCase('true');
    }

    public String getPaymentStatusLabel() {
        if (getPaidOverride()) return 'PAID';
        if (invoice == null) return 'DRAFT';
        String s = invoice.Stripe_Payment_Status__c;
        if (s == 'Paid') return 'PAID';
        if (s == 'Sent') return 'AWAITING PAYMENT';
        if (s == 'Failed') return 'PAYMENT FAILED';
        return 'DRAFT';
    }

    public String getPaymentStatusKey() {
        if (getPaidOverride()) return 'paid';
        if (invoice == null) return 'draft';
        String s = invoice.Stripe_Payment_Status__c;
        if (s == 'Paid') return 'paid';
        if (s == 'Sent') return 'pending';
        if (s == 'Failed') return 'failed';
        return 'draft';
    }

    public String getDocumentLabel() {
        return (getPaymentStatusKey() == 'paid') ? 'RECEIPT' : 'INVOICE';
    }

    public String getDocumentTagline() {
        return (getPaymentStatusKey() == 'paid') ? 'PAYMENT RECEIPT' : 'REVENUE CLOUD EXCELLENCE';
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
        if (getPaidOverride()) return true;
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
        public String listPriceFormatted { get; set; }
        public String discountPercentStr { get; set; }
        public String netPriceFormatted { get; set; }
        public String unitPriceFormatted { get; set; }
        public String taxFormatted { get; set; }
        public String lineTotalFormatted { get; set; }

        public InvoiceLineWrapper(InvoiceLine l, OrderItem matchedOi) {
            line = l;
            productName = (l.Product2 != null && l.Product2.Name != null) ? l.Product2.Name : 'Service';

            if (l.InvoiceLineStartDate != null && l.InvoiceLineEndDate != null) {
                periodStr = l.InvoiceLineStartDate.format() + ' — ' + l.InvoiceLineEndDate.format();
            } else {
                periodStr = '—';
            }

            quantityStr = (l.Quantity == null) ? '—' : l.Quantity.setScale(0).format();

            Decimal currentUnit = (l.UnitPrice == null) ? 0 : l.UnitPrice;
            Decimal listPrice = (matchedOi != null && matchedOi.ListPrice != null) ? matchedOi.ListPrice : currentUnit;

            Decimal discountPct = 0;
            if (listPrice > 0 && listPrice > currentUnit) {
                discountPct = ((listPrice - currentUnit) / listPrice * 100).setScale(1);
            }

            Decimal qty = (l.Quantity == null) ? 1 : l.Quantity;
            Decimal lineGross = currentUnit * qty;
            Decimal lineNet = (lineGross / (1 + VAT_RATE)).setScale(2);
            Decimal lineTax = (lineGross - lineNet).setScale(2);

            listPriceFormatted = formatCurrency(listPrice);
            discountPercentStr = (discountPct == 0) ? '—' : discountPct.format() + '%';
            netPriceFormatted = formatCurrency(currentUnit);
            unitPriceFormatted = formatCurrency(currentUnit);
            taxFormatted = formatCurrency(lineTax);
            lineTotalFormatted = formatCurrency(lineGross);
        }
    }
}
