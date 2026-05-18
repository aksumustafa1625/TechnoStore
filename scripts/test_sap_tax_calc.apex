// Phase 3 end-to-end test on an existing Invoice
List<Invoice> invs = [SELECT Id, DocumentNumber, TotalAmount, BillingAccount.BillingCountry FROM Invoice WHERE TotalAmount > 0 ORDER BY CreatedDate DESC LIMIT 1];
if (invs.isEmpty()) { System.debug('No Invoice with TotalAmount > 0 — abort'); return; }
Invoice inv = invs[0];
System.debug('Testing on Invoice ' + inv.DocumentNumber + ' (Country=' + (inv.BillingAccount != null ? inv.BillingAccount.BillingCountry : 'null') + ', Total=' + inv.TotalAmount + ')');

SapTaxCalculationService.Request req = new SapTaxCalculationService.Request();
req.invoiceId = inv.Id;
List<SapTaxCalculationService.Result> results = SapTaxCalculationService.calculateForInvoice(new List<SapTaxCalculationService.Request>{ req });

for (SapTaxCalculationService.Result r : results) {
    System.debug('=== Tax calc result ===');
    System.debug('  invoiceId    = ' + r.invoiceId);
    System.debug('  taxRate      = ' + r.taxRate + '%');
    System.debug('  taxAmount    = ' + r.taxAmount);
    System.debug('  engineUsed   = ' + r.engineUsed);
    System.debug('  status       = ' + r.status);
    System.debug('  message      = ' + r.message);
}

Invoice check = [SELECT DocumentNumber, SAP_Tax_Rate__c, SAP_Tax_Amount__c, SAP_Tax_Calculated_At__c, Tax_Engine_Used__c FROM Invoice WHERE Id = :inv.Id];
System.debug('=== Invoice fields after call ===');
System.debug('  SAP_Tax_Rate__c          = ' + check.SAP_Tax_Rate__c);
System.debug('  SAP_Tax_Amount__c        = ' + check.SAP_Tax_Amount__c);
System.debug('  SAP_Tax_Calculated_At__c = ' + check.SAP_Tax_Calculated_At__c);
System.debug('  Tax_Engine_Used__c       = ' + check.Tax_Engine_Used__c);
