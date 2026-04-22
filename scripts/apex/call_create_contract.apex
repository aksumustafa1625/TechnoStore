String quoteId = '0Q0aj000002CmNtCAK';
Invocable.Action action = Invocable.Action.createStandardAction('createContract');
action.setInvocationParameter('sourceId', quoteId);
List<Invocable.Action.Result> results = action.invoke();
Id cid = null;
for (Invocable.Action.Result r : results) {
    if (r.isSuccess()) {
        cid = (Id) r.getOutputParameters().get('contractId');
        System.debug('SUCCESS: contractId=' + cid);
    } else {
        System.debug('ERRORS_FOUND: ' + JSON.serialize(r.getErrors()));
    }
}

if (cid != null) {
    System.debug('LINE_COUNT=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
    for (SalesContractLine scl : [SELECT Id, Name, Product2Id, Quantity FROM SalesContractLine WHERE ContractId = :cid]) {
        System.debug('LINE: ' + scl.Name + ' qty=' + scl.Quantity);
    }
}