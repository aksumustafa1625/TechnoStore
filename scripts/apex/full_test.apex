// 1. Create a fresh test Quote with a line item
Opportunity opp = [SELECT Id, Pricebook2Id, AccountId FROM Opportunity WHERE AccountId != null LIMIT 1];
Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Id pbId = opp.Pricebook2Id != null ? opp.Pricebook2Id : pb.Id;
Quote q = new Quote(Name='TEST_'+DateTime.now().format('HHmmss'), OpportunityId=opp.Id, Pricebook2Id=pbId, Status='Draft');
insert q;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :pbId AND IsActive = true LIMIT 1];
QuoteLineItem qli = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbe.Id, Product2Id=pbe.Product2Id, Quantity=1, UnitPrice=pbe.UnitPrice);
insert qli;
System.debug('QUOTE=' + q.Id + ' | QLI=' + qli.Id);

// 2. Call createContract invocable
Invocable.Action action = Invocable.Action.createStandardAction('createContract');
action.setInvocationParameter('sourceId', String.valueOf(q.Id));
List<Invocable.Action.Result> results = action.invoke();

Id cid = null;
for (Invocable.Action.Result r : results) {
    if (r.isSuccess()) {
        cid = (Id) r.getOutputParameters().get('contractId');
        System.debug('SUCCESS contract=' + cid);
    } else {
        System.debug('FAILED: ' + JSON.serialize(r.getErrors()));
    }
}

// 3. Verify lines created
if (cid != null) {
    Integer c = [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid];
    System.debug('LINES=' + c);
    for (SalesContractLine scl : [SELECT Id, Name, Product2Id, Quantity FROM SalesContractLine WHERE ContractId = :cid]) {
        System.debug('LINE: ' + scl.Name + ' qty=' + scl.Quantity);
    }
}