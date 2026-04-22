// Populate Description on all QLIs for this test quote
List<QuoteLineItem> qlis = [SELECT Id, Description, Product2.Name FROM QuoteLineItem WHERE QuoteId = '0Q0aj000002CmqvCAC'];
for (QuoteLineItem q : qlis) {
    q.Description = 'Line - ' + (q.Product2 != null ? q.Product2.Name : 'Unknown');
}
update qlis;
for (QuoteLineItem q : qlis) {
    System.debug('QLI='+q.Id+' desc='+q.Description);
}

// Delete the existing created contracts for this quote
List<Contract> oc = [SELECT Id FROM Contract WHERE SourceQuoteId = '0Q0aj000002CmqvCAC'];
if (!oc.isEmpty()) delete oc;

// Test
Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', '0Q0aj000002CmqvCAC');
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) {
        Object raw = r.getOutputParameters().get('contractId');
        Id cid;
        if (raw instanceof List<Object>) cid = (Id) ((List<Object>) raw)[0];
        else cid = (Id) raw;
        System.debug('SUCCESS contract=' + cid);
        System.debug('LINES=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
        for (SalesContractLine scl : [SELECT Name, Product2.Name, Quantity FROM SalesContractLine WHERE ContractId = :cid]) {
            System.debug('LINE: Name="' + scl.Name + '" product=' + scl.Product2.Name);
        }
    } else {
        System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
    }
}