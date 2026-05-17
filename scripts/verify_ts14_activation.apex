// Test the audit-only approval cycle (Inventory_Audit_Approval) on Order 00000170
// This simulates what the handler does in Pass 4.
Order o = [SELECT Id, OrderNumber, Status, JIRA_Ticket_Id__c FROM Order WHERE OrderNumber = '00000170' LIMIT 1];
System.debug('Testing on ' + o.OrderNumber + ' Status=' + o.Status + ' JIRA=' + o.JIRA_Ticket_Id__c);

String confirmedBy = 'JIRA ' + o.JIRA_Ticket_Id__c;

try {
    Approval.ProcessSubmitRequest sub = new Approval.ProcessSubmitRequest();
    sub.setObjectId(o.Id);
    sub.setProcessDefinitionNameOrId('Inventory_Audit_Approval');
    sub.setComments('Audit cycle for ' + confirmedBy + ' transition to Done.');
    sub.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
    Approval.ProcessResult subResult = Approval.process(sub);

    System.debug('Submit success: ' + subResult.isSuccess());
    if (subResult.isSuccess()) {
        System.debug('  ProcessInstanceId: ' + subResult.getInstanceId());
        Id wiId = subResult.getNewWorkitemIds()[0];
        Approval.ProcessWorkitemRequest wiReq = new Approval.ProcessWorkitemRequest();
        wiReq.setWorkitemId(wiId);
        wiReq.setAction('Approve');
        wiReq.setComments('Inventory confirmed in stock via ' + confirmedBy + '.');
        Approval.ProcessResult approveResult = Approval.process(wiReq);
        System.debug('Approve success: ' + approveResult.isSuccess());
    } else {
        for (Database.Error err : subResult.getErrors()) {
            System.debug('  Error: ' + err.getMessage());
        }
    }
} catch (Exception e) {
    System.debug('EXCEPTION: ' + e.getMessage());
    System.debug(e.getStackTraceString());
}

// Verify the new ProcessInstance + Step exists
System.debug('');
System.debug('Process Instances on Order:');
for (ProcessInstance pi : [SELECT Id, Status, CompletedDate, TargetObjectId FROM ProcessInstance WHERE TargetObjectId = :o.Id ORDER BY CompletedDate DESC NULLS LAST LIMIT 5]) {
    System.debug('  PI ' + pi.Id + ' Status=' + pi.Status + ' Completed=' + pi.CompletedDate);
    for (ProcessInstanceStep step : [SELECT Comments, StepStatus, ActorId, CreatedDate FROM ProcessInstanceStep WHERE ProcessInstanceId = :pi.Id ORDER BY CreatedDate DESC]) {
        System.debug('    Step status=' + step.StepStatus + ' comment="' + step.Comments + '"');
    }
}
