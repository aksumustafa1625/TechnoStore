// Use "Test 5" quote (QLIs exist)
String quoteId = '0Q0aj000002ClEvCAK';

// Delete existing contract
List<Contract> oc = [SELECT Id FROM Contract WHERE SourceQuoteId = :quoteId];
if (!oc.isEmpty()) delete oc;
System.debug('Removed old: ' + oc.size());

Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', quoteId);
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) {
        Object raw = r.getOutputParameters().get('contractId');
        Id cid = (raw instanceof List<Object>) ? (Id)((List<Object>)raw)[0] : (Id) raw;
        System.debug('SUCCESS cid=' + cid);
        System.debug('LINES=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
        for (SalesContractLine s : [SELECT Name, Product2.Name, Quantity, TotalPrice FROM SalesContractLine WHERE ContractId = :cid])
            System.debug('LINE: "' + s.Name + '" product=' + s.Product2.Name + ' qty=' + s.Quantity + ' total=' + s.TotalPrice);
    } else {
        System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
    }
}