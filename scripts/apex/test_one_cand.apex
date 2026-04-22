// Call createClmContract on an existing fresh Quote
String quoteId = '0Q0aj000002CmqvCAC';

// Delete existing Contract for this quote first if any
List<Contract> existing = [SELECT Id FROM Contract WHERE SourceQuoteId = :quoteId];
if (!existing.isEmpty()) delete existing;

Invocable.Action action = Invocable.Action.createStandardAction('createClmContract');
action.setInvocationParameter('sourceRecordId', quoteId);
List<Invocable.Action.Result> results = action.invoke();

for (Invocable.Action.Result r : results) {
    if (r.isSuccess()) {
        Id cid = (Id) r.getOutputParameters().get('contractId');
        System.debug('SUCCESS contract='+cid);
        System.debug('LINES=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
    } else {
        System.debug('FAIL: '+JSON.serialize(r.getErrors()));
    }
}