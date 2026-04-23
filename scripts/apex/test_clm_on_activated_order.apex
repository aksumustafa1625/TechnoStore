// Test createClmContract on Activated Order 00000137
Order o = [SELECT Id, OrderNumber, Status, ContractId FROM Order WHERE OrderNumber='00000137' LIMIT 1];
System.debug('Order 137: Status=' + o.Status + ' existingContractId=' + o.ContractId);

if (o.ContractId != null) {
    System.debug('ALREADY has contract - skipping test');
} else {
    Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
    a.setInvocationParameter('sourceRecordId', String.valueOf(o.Id));
    List<Invocable.Action.Result> rs = a.invoke();
    for (Invocable.Action.Result r : rs) {
        if (r.isSuccess()) {
            Object raw = r.getOutputParameters().get('contractId');
            Id cid = (raw instanceof List<Object>) ? (Id)((List<Object>)raw)[0] : (Id) raw;
            System.debug('SUCCESS cid=' + cid);
            for (SalesContractLine s : [SELECT Name, Product2.Name, Quantity, TotalPrice FROM SalesContractLine WHERE ContractId = :cid]) {
                System.debug('LINE: ' + s.Name + ' qty=' + s.Quantity + ' total=' + s.TotalPrice);
            }
        } else {
            System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
        }
    }
}
