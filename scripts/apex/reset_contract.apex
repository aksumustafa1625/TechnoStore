Contract c = [SELECT Id, Status FROM Contract WHERE Id='800aj00002Z2VIfAAN' LIMIT 1];
List<ProcessInstance> pending = [SELECT Id, Status, TargetObjectId FROM ProcessInstance
                                 WHERE TargetObjectId=:c.Id AND Status='Pending'];
for (ProcessInstance pi : pending) {
    List<ProcessInstanceWorkitem> items = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstanceId=:pi.Id];
    for (ProcessInstanceWorkitem item : items) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setAction('Removed');
        req.setWorkitemId(item.Id);
        req.setComments('Auto-reset for retest');
        Approval.process(req);
    }
}
c.Status = 'Draft';
update c;
System.debug('Contract reset to Draft: ' + c.Id);
