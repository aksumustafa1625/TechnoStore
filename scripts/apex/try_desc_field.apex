Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

// Set Name attribute to Description (direct field) FIRST (callouts before DML)
HttpRequest req = new HttpRequest();
req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextAttributeMapping/11Raj000007hbE1EAI');
req.setMethod('PATCH');
req.setHeader('Authorization', 'Bearer ' + sessionId);
req.setHeader('Content-Type', 'application/json');
req.setBody('{"ContextInputAttributeName":"Description"}');
System.debug('PATCH: ' + http.send(req).getStatusCode());

// test
Invocable.Action a = Invocable.Action.createStandardAction('createClmContract');
a.setInvocationParameter('sourceRecordId', '0Q0aj000002CmqvCAC');
List<Invocable.Action.Result> rs = a.invoke();
for (Invocable.Action.Result r : rs) {
    if (r.isSuccess()) System.debug('SUCCESS: ' + r.getOutputParameters().get('contractId'));
    else System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
}