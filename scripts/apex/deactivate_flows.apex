// Deactivate Order_To_Billing_Schedule flow definition (set ActiveVersionId to null)
String defId = '300aj00002RZoO1AAL';
String token = UserInfo.getSessionId();
String base = URL.getOrgDomainUrl().toExternalForm();

HttpRequest req = new HttpRequest();
req.setEndpoint(base + '/services/data/v63.0/tooling/sobjects/FlowDefinition/' + defId);
req.setMethod('PATCH');
req.setHeader('Authorization', 'Bearer ' + token);
req.setHeader('Content-Type', 'application/json');
req.setBody('{"Metadata":{"activeVersionNumber":null}}');
HttpResponse res = new Http().send(req);
System.debug('=STATUS=' + res.getStatusCode() + ' BODY=' + res.getBody());
