Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

// Set back to Product2.Name
for (String mapId : new List<String>{'11Raj000007hbE1EAI','11Raj000007hbDaEAI'}) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextAttributeMapping/' + mapId);
    req.setMethod('PATCH');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"ContextInputAttributeName":"Product2.Name"}');
    System.debug(mapId + ' => ' + http.send(req).getStatusCode());
}

// Create fresh test Quote
Opportunity opp = [SELECT Id, Pricebook2Id FROM Opportunity WHERE AccountId != null LIMIT 1];
Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Id pbId = opp.Pricebook2Id != null ? opp.Pricebook2Id : pb.Id;
Quote q = new Quote(Name='P2_TEST', OpportunityId=opp.Id, Pricebook2Id=pbId, Status='Draft');
insert q;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :pbId AND IsActive = true LIMIT 1];
insert new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbe.Id, Product2Id=pbe.Product2Id, Quantity=1, UnitPrice=pbe.UnitPrice);
// Do NOT set Description

Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', String.valueOf(q.Id));
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) {
        Object raw = r.getOutputParameters().get('contractId');
        Id cid = (raw instanceof List<Object>) ? (Id)((List<Object>)raw)[0] : (Id) raw;
        System.debug('SUCCESS cid=' + cid);
        System.debug('LINES=' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
        for (SalesContractLine s : [SELECT Name, Product2.Name FROM SalesContractLine WHERE ContractId = :cid]) System.debug('LINE: ' + s.Name);
    } else {
        System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
    }
}