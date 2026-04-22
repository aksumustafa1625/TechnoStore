// Test createClmContract on Opportunity (should work since Opp mappings existed)
Opportunity opp = [SELECT Id, Name, AccountId FROM Opportunity WHERE AccountId != null LIMIT 1];
System.debug('Testing Opp: ' + opp.Id + ' | ' + opp.Name);

Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', String.valueOf(opp.Id));
a.setInvocationParameter('contractRecordType', 'ContractLifecycleManagement');
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) System.debug('OK contractId='+r.getOutputParameters().get('contractId'));
    else System.debug('FAIL: '+JSON.serialize(r.getErrors()));
}