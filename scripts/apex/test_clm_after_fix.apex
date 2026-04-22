// Delete existing contract for 0Q0aj000002CmqvCAC
List<Contract> oc = [SELECT Id FROM Contract WHERE SourceQuoteId = '0Q0aj000002CmqvCAC'];
if (!oc.isEmpty()) delete oc;
oc = [SELECT Id FROM Contract WHERE AccountId IN (SELECT AccountId FROM Quote WHERE Id='0Q0aj000002CmqvCAC') AND Status = 'Draft'];
// Don't delete these - just report
System.debug('Drafts for quote account: ' + oc.size());

Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', '0Q0aj000002CmqvCAC');
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) {
        Id cid = (Id) r.getOutputParameters().get('contractId');
        System.debug('SUCCESS: '+cid);
        System.debug('LINES=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
        for (SalesContractLine s : [SELECT Name, Product2.Name FROM SalesContractLine WHERE ContractId = :cid]) {
            System.debug('LINE: '+s.Name+' ('+s.Product2.Name+')');
        }
    } else {
        System.debug('FAIL: '+JSON.serialize(r.getErrors()));
    }
}