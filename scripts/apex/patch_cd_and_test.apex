// Patch ContextDefinitionName via callout (no DML first)
Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();
String target = 'Custom_ContractsContext';

for (String mapId : new List<String>{'1C6aj000000APunCAG', '1C6aj000000AT7BCAW'}) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/' + mapId);
    req.setMethod('PATCH');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"ContextDefinitionName":"' + target + '"}');
    System.debug(mapId + ' => ' + http.send(req).getStatusCode());
}

// Now test
Invocable.Action action = Invocable.Action.createStandardAction('createClmContract');
action.setInvocationParameter('sourceRecordId', '0Q0aj000002CmqvCAC');
List<Invocable.Action.Result> results = action.invoke();
for (Invocable.Action.Result r : results) {
    if (r.isSuccess()) {
        System.debug('SUCCESS contractId=' + r.getOutputParameters().get('contractId'));
    } else {
        System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
    }
}