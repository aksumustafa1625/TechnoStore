Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
req.setObjectId('800aj00002Z2VIfAAN');
req.setComments('Test submission');
try {
    Approval.ProcessResult result = Approval.process(req);
    System.debug('SUCCESS: ' + result.isSuccess());
    System.debug('Status: ' + result.getInstanceStatus());
    for (Database.Error err : result.getErrors()) {
        System.debug('ERROR: ' + err.getMessage());
    }
} catch (Exception e) {
    System.debug('EXCEPTION: ' + e.getMessage());
}
