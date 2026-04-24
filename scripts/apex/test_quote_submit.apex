Quote q = [SELECT Id, Name, Discount, Status, OwnerId FROM Quote WHERE Id='0Q0aj000002DPNdCAO'];
System.debug('Quote: ' + q.Name + ' | Discount: ' + q.Discount + ' | Status: ' + q.Status);

Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
req.setObjectId(q.Id);
req.setComments('Test submission');
try {
    Approval.ProcessResult result = Approval.process(req);
    System.debug('SUCCESS: ' + result.isSuccess() + ' | Status: ' + result.getInstanceStatus());
    for (Database.Error err : result.getErrors()) {
        System.debug('  ERR: ' + err.getMessage() + ' | Fields: ' + err.getFields());
    }
} catch (Exception e) {
    System.debug('EXCEPTION: ' + e.getMessage() + ' | Type: ' + e.getTypeName());
}
