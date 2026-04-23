List<ProcessInstance> pending = [SELECT Id FROM ProcessInstance
                                 WHERE TargetObjectId='800aj00002Z2VIfAAN' AND Status='Pending'];
List<ProcessInstanceWorkitem> items = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstanceId IN :pending];
for (ProcessInstanceWorkitem item : items) {
    Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
    req.setAction('Approve');
    req.setWorkitemId(item.Id);
    req.setComments('Auto-approve to test finalApprovalActions');
    Approval.process(req);
}
Contract c = [SELECT Id, ContractNumber, Status FROM Contract WHERE Id='800aj00002Z2VIfAAN'];
System.debug('Contract ' + c.ContractNumber + ' status after approval: ' + c.Status);
