public with sharing class GenerateOrderInvoiceService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Response {
        @InvocableVariable(label='Demo Invoice Id')
        public Id invoiceId;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Generate Demo Invoice from Order')
    public static List<Response> generate(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request r : requests) {
            results.add(generateOne(r.orderId));
        }
        return results;
    }

    private static Response generateOne(Id orderId) {
        Response resp = new Response();
        try {
            Order ord = [
                SELECT Id, OrderNumber, AccountId, TotalAmount, EffectiveDate
                FROM Order WHERE Id = :orderId LIMIT 1
            ];

            List<BillingSchedule> bsList = [
                SELECT Id, BillingScheduleNumber, TotalAmount, BillingType,
                       BillingScheduleStartDate, BillingScheduleEndDate, Status
                FROM BillingSchedule
                WHERE ReferenceEntityId = :orderId
                ORDER BY CreatedDate DESC LIMIT 1
            ];

            Decimal total = bsList.isEmpty() ? ord.TotalAmount : bsList[0].TotalAmount;
            String bsId = bsList.isEmpty() ? null : bsList[0].Id;
            Date invoiceDate = Date.today();
            Date dueDate = invoiceDate.addDays(30);

            Demo_Invoice__c inv = new Demo_Invoice__c(
                Order__c = orderId,
                Account__c = ord.AccountId,
                Invoice_Date__c = invoiceDate,
                Due_Date__c = dueDate,
                Total_Amount__c = total,
                Status__c = 'Draft',
                Billing_Schedule_Id__c = bsId
            );
            insert inv;

            resp.invoiceId = inv.Id;
            resp.status = 'Draft';
            resp.message = 'Invoice generated for Order ' + ord.OrderNumber + ' with amount ' + String.valueOf(total);
        } catch (Exception e) {
            resp.status = 'Error';
            resp.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return resp;
    }
}
