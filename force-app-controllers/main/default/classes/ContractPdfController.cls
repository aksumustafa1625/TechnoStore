/**
 * Backing controller for TechnoStoreContractPdf VF page.
 *
 * Renders a professional Master Service Agreement PDF for a Contract.
 * Bypasses the broken native CLM Document Template flow — generates the
 * PDF entirely from this controller + VF page, then links to Contract via
 * ContentDocumentLink (separate Apex service handles the file insert).
 */
public with sharing class ContractPdfController {

    public Contract contractRecord { get; set; }
    public Account billingAccount { get; set; }
    public Contact billToContact { get; set; }
    public List<OrderItemWrapper> orderItems { get; set; }
    public Decimal totalAmount { get; set; }

    public ContractPdfController() {
        orderItems = new List<OrderItemWrapper>();
        totalAmount = 0;
        Id contractId = ApexPages.currentPage().getParameters().get('id');
        if (contractId != null) {
            loadData(contractId);
        }
    }

    public class OrderItemWrapper {
        public String productName { get; set; }
        public String quantityStr { get; set; }
        public String unitPriceStr { get; set; }
        public String totalPriceStr { get; set; }

        public OrderItemWrapper(OrderItem oi) {
            productName = (oi.Product2 != null && oi.Product2.Name != null) ? oi.Product2.Name : 'Service';
            quantityStr = oi.Quantity == null ? '1' : String.valueOf(oi.Quantity.intValue());
            unitPriceStr = oi.UnitPrice == null ? '$0.00' : '$' + oi.UnitPrice.setScale(2).format();
            totalPriceStr = oi.TotalPrice == null ? '$0.00' : '$' + oi.TotalPrice.setScale(2).format();
        }
    }

    private void loadData(Id contractId) {
        List<Contract> results = [
            SELECT Id, ContractNumber, Status, StartDate, EndDate, ContractTerm,
                   Description, AccountId,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   CustomerSignedTitle, CustomerSignedDate, CompanySignedDate
            FROM Contract WHERE Id = :contractId LIMIT 1
        ];
        if (results.isEmpty()) return;
        contractRecord = results[0];

        if (contractRecord.AccountId != null) {
            List<Account> accs = [
                SELECT Id, Name, Phone, Website, Industry, AnnualRevenue, NumberOfEmployees,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account WHERE Id = :contractRecord.AccountId LIMIT 1
            ];
            if (!accs.isEmpty()) billingAccount = accs[0];

            List<Contact> contacts = [
                SELECT Id, Name, Salutation, FirstName, LastName, Title, Email, Phone
                FROM Contact WHERE AccountId = :contractRecord.AccountId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!contacts.isEmpty()) billToContact = contacts[0];

            // Pull line items via Order linked to this Contract
            List<Order> orders = [
                SELECT Id FROM Order
                WHERE ContractId = :contractRecord.Id AND Status = 'Activated'
                ORDER BY EffectiveDate DESC LIMIT 1
            ];
            if (!orders.isEmpty()) {
                List<OrderItem> items = [
                    SELECT Id, Quantity, UnitPrice, TotalPrice, Product2.Name
                    FROM OrderItem WHERE OrderId = :orders[0].Id
                    ORDER BY CreatedDate ASC
                ];
                for (OrderItem oi : items) {
                    orderItems.add(new OrderItemWrapper(oi));
                    if (oi.TotalPrice != null) totalAmount += oi.TotalPrice;
                }
            }
        }
    }

    public String getTotalAmountStr() {
        return '$' + totalAmount.setScale(2).format();
    }

    public Boolean getHasOrderItems() {
        return orderItems != null && !orderItems.isEmpty();
    }

    public String getEffectiveDateStr() {
        return (contractRecord == null || contractRecord.StartDate == null) ? Date.today().format() : contractRecord.StartDate.format();
    }

    public String getEndDateStr() {
        return (contractRecord == null || contractRecord.EndDate == null) ? Date.today().addYears(1).format() : contractRecord.EndDate.format();
    }

    public String getContractNumberStr() {
        return (contractRecord == null || contractRecord.ContractNumber == null) ? 'C-DRAFT' : contractRecord.ContractNumber;
    }

    public String getCustomerName() {
        return (billingAccount == null || billingAccount.Name == null) ? 'Customer' : billingAccount.Name;
    }

    public String getCustomerCity() {
        return (billingAccount == null) ? '' :
            ((billingAccount.BillingPostalCode == null ? '' : billingAccount.BillingPostalCode + ' ') +
             (billingAccount.BillingCity == null ? '' : billingAccount.BillingCity));
    }

    public String getCustomerStreet() {
        return (billingAccount == null || billingAccount.BillingStreet == null) ? '' : billingAccount.BillingStreet;
    }

    public String getCustomerCountry() {
        return (billingAccount == null || billingAccount.BillingCountry == null) ? '' : billingAccount.BillingCountry;
    }

    public String getContactName() {
        return (billToContact == null || billToContact.Name == null) ? 'Authorized Representative' : billToContact.Name;
    }

    public String getContactTitle() {
        return (billToContact == null || billToContact.Title == null) ? '' : billToContact.Title;
    }

    public String getContactEmail() {
        return (billToContact == null || billToContact.Email == null) ? '' : billToContact.Email;
    }
}
