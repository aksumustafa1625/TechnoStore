Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

// Find active version
ContextDefinitionVersion v = [SELECT Id, VersionNumber, IsActive FROM ContextDefinitionVersion WHERE ContextDefinition.DeveloperName = 'Custom_ContractsContext' AND IsActive = true LIMIT 1];
System.debug('Current active version=' + v.VersionNumber + ' Id=' + v.Id);

// Deactivate
HttpRequest rd = new HttpRequest();
rd.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextDefinitionVersion/' + v.Id);
rd.setMethod('PATCH');
rd.setHeader('Authorization', 'Bearer ' + sessionId);
rd.setHeader('Content-Type', 'application/json');
rd.setBody('{"IsActive":false}');
System.debug('DEACTIVATE: ' + http.send(rd).getStatusCode());

// Reactivate
HttpRequest ra = new HttpRequest();
ra.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextDefinitionVersion/' + v.Id);
ra.setMethod('PATCH');
ra.setHeader('Authorization', 'Bearer ' + sessionId);
ra.setHeader('Content-Type', 'application/json');
ra.setBody('{"IsActive":true}');
System.debug('REACTIVATE: ' + http.send(ra).getStatusCode());

// Trigger Sync
HttpRequest rs = new HttpRequest();
rs.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextDefinitionSync/');
rs.setMethod('POST');
rs.setHeader('Authorization', 'Bearer ' + sessionId);
rs.setHeader('Content-Type', 'application/json');
rs.setBody('{"ContextDefinitionName":"Custom_ContractsContext","Status":"in_progress","StartDateTime":"' + DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '"}');
HttpResponse rsRes = http.send(rs);
System.debug('SYNC: ' + rsRes.getStatusCode() + ' : ' + rsRes.getBody());