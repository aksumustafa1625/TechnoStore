// Update ContextAttributeMapping via REST callout from within Apex
Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();

// Use session Id from UserInfo
String sessionId = UserInfo.getSessionId();

List<Id> ids = new List<Id>{'11Raj000007hbE1EAI','11Raj000007hbDaEAI'};
String newValue = 'Product2.Name';

for (Id rid : ids) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextAttributeMapping/' + rid);
    req.setMethod('PATCH');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"ContextInputAttributeName":"' + newValue + '"}');
    HttpResponse res = http.send(req);
    System.debug('PATCH ' + rid + ' => ' + res.getStatusCode() + ' : ' + res.getBody());
}

// Verify
for (ContextAttributeMapping m : [SELECT Id, ContextInputAttributeName, ContextNodeMapping.Object FROM ContextAttributeMapping WHERE Id IN :ids]) {
    System.debug('VERIFY: '+m.Id+' obj='+m.ContextNodeMapping.Object+' => '+m.ContextInputAttributeName);
}