// Try different ContextDefinitionName values for Quote mapping, one at a time
Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

List<String> candidates = new List<String>{
    'ContractsContextDefinition',       // no suffix
    'Custom_ContractsContext',           // existing
    'ContractsContextDefinition__stdctx' // current
};

// Quote Hydration mapping Id (needs to match): 1C6aj000000APunCAG
// Quote Persistence mapping Id: 1C6aj000000AT7BCAW

for (String cand : candidates) {
    // Update both Quote mappings
    for (String mapId : new List<String>{'1C6aj000000APunCAG', '1C6aj000000AT7BCAW'}) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/' + mapId);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{"ContextDefinitionName":"' + cand + '"}');
        http.send(req);
    }

    // Create a fresh Quote
    Opportunity opp = [SELECT Id, Pricebook2Id, AccountId FROM Opportunity WHERE AccountId != null LIMIT 1];
    Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
    Id pbId = opp.Pricebook2Id != null ? opp.Pricebook2Id : pb.Id;
    Quote q = new Quote(Name='CT_'+cand.substring(0,6)+DateTime.now().format('HHmmss'), OpportunityId=opp.Id, Pricebook2Id=pbId, Status='Draft');
    insert q;
    PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :pbId AND IsActive = true LIMIT 1];
    insert new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbe.Id, Product2Id=pbe.Product2Id, Quantity=1, UnitPrice=pbe.UnitPrice);

    // Call createClmContract
    Invocable.Action action = Invocable.Action.createStandardAction('createClmContract');
    action.setInvocationParameter('sourceRecordId', String.valueOf(q.Id));
    List<Invocable.Action.Result> results = action.invoke();
    for (Invocable.Action.Result r : results) {
        if (r.isSuccess()) {
            System.debug('CAND='+cand+' SUCCESS contractId='+r.getOutputParameters().get('contractId'));
        } else {
            System.debug('CAND='+cand+' FAIL: '+JSON.serialize(r.getErrors()));
        }
    }
}