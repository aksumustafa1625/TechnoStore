Map<String, Object> params = new Map<String, Object>{
    'recordId' => '800aj00002Z2VIfAAN',
    'Comments' => 'Test via custom flow'
};
try {
    Flow.Interview flow = Flow.Interview.createInterview('Submit_Contract_For_Approval', params);
    flow.start();
    System.debug('Flow executed');
} catch (Exception e) {
    System.debug('FLOW ERROR: ' + e.getMessage() + ' :: ' + e.getTypeName());
}
Contract c = [SELECT Id, Status FROM Contract WHERE Id='800aj00002Z2VIfAAN'];
System.debug('Contract status now: ' + c.Status);
