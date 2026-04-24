List<ProcessInstance> pending = [SELECT Id FROM ProcessInstance WHERE TargetObjectId='0Q0aj000002DPNdCAO' AND Status='Pending'];
List<ProcessInstanceWorkitem> items = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstanceId IN :pending];
for (ProcessInstanceWorkitem w : items) {
    Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
    req.setAction('Removed');
    req.setWorkitemId(w.Id);
    req.setComments('Reset for UI test');
    Approval.process(req);
}
Quote q = [SELECT Id, Status FROM Quote WHERE Id='0Q0aj000002DPNdCAO'];
q.Status = 'Draft';
update q;
System.debug('Quote reset to Draft. Discount kept at 25%.');
