// Simulate both scenarios: 10% and 25% discount

// Scenario 1: quote with discount 10% - should match NO approval process (auto-approve path in flow)
List<Quote> qList = [SELECT Id, Discount FROM Quote WHERE Discount != null AND Discount > 0 ORDER BY Discount ASC LIMIT 1];
if (!qList.isEmpty()) {
    Quote q = qList[0];
    System.debug('Test quote: ' + q.Id + ' | Discount: ' + q.Discount);

    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
    req.setObjectId(q.Id);
    req.setComments('threshold test');
    try {
        Approval.ProcessResult r = Approval.process(req);
        System.debug('Submit result: ' + r.isSuccess() + ' (discount=' + q.Discount + ')');
    } catch (Exception e) {
        System.debug('Discount ' + q.Discount + ' -> ' + (e.getMessage().contains('NO_APPLICABLE_PROCESS') ? 'NO_APPROVAL (auto-approve path)' : e.getMessage()));
    }
}
