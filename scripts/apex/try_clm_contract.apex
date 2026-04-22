// Explore createClmContract action schema
Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

HttpRequest req = new HttpRequest();
req.setEndpoint(baseUrl + '/services/data/v63.0/actions/standard/createClmContract');
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + sessionId);
HttpResponse res = http.send(req);
System.debug('SCHEMA: ' + res.getBody());