// Why didn't the Status=Paid update work? Try directly + capture errors.
Invoice inv = [SELECT Id, DocumentNumber, Status, Payment_Method__c FROM Invoice WHERE DocumentNumber = 'DOC-000000017'];
System.debug('Before: ' + inv.Status);

Invoice upd = new Invoice(Id = inv.Id, Status = 'Paid', Payment_Method__c = 'Bank_Transfer');
Database.SaveResult sr = Database.update(upd, false);
if (sr.isSuccess()) {
    System.debug('Success — direct update worked');
} else {
    for (Database.Error err : sr.getErrors()) {
        System.debug('ERROR: ' + err.getStatusCode() + ' | ' + err.getMessage() + ' | fields=' + err.getFields());
    }
}

// Check valid Status picklist values
Schema.DescribeFieldResult dfr = Invoice.Status.getDescribe();
System.debug('Invoice.Status picklist values:');
for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
    System.debug('  ' + pe.getValue() + ' / active=' + pe.isActive());
}
