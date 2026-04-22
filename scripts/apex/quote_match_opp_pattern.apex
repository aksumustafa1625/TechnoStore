// 1. Change Quote existing records back to stdctx (they already have RT set)
Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

for (String mapId : new List<String>{'1C6aj000000APunCAG', '1C6aj000000AT7BCAW'}) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/' + mapId);
    req.setMethod('PATCH');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"ContextDefinitionName":"ContractsContextDefinition__stdctx"}');
    System.debug('switch ' + mapId + ' -> ' + http.send(req).getStatusCode());
}

// 2. Create the "plain" style records (no RT, no CustomField for Hydration, SourceQuoteId for Persistence)
// These mirror the Opp plain records that live alongside timestamped ones

// Check if already exist
List<ContextUseCaseMapping> plains = [SELECT Id FROM ContextUseCaseMapping WHERE DeveloperName IN ('QuoteToCntrHydrationMapping_plain', 'QuoteToCntrPersistenceMapping_plain')];
for (ContextUseCaseMapping m : plains) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/' + m.Id);
    req.setMethod('DELETE');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    http.send(req);
}

// Hydration plain
HttpRequest rh = new HttpRequest();
rh.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/');
rh.setMethod('POST');
rh.setHeader('Authorization', 'Bearer ' + sessionId);
rh.setHeader('Content-Type', 'application/json');
rh.setBody('{"DeveloperName":"QuoteToCntrHydrationMapping_plain","MasterLabel":"QuoteToCntrHydrationMapping","ReferenceObjectName":"Quote","TargetObjectName":"Contract","ContextDefinitionName":"ContractsContextDefinition__stdctx","MappingName":"QuoteToCntrHydrationMapping","MappingType":"Hydration","UseCaseType":"ContractCreationOrUpdation"}');
System.debug('hyd plain: ' + http.send(rh).getBody());

// Persistence plain
HttpRequest rp = new HttpRequest();
rp.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextUseCaseMapping/');
rp.setMethod('POST');
rp.setHeader('Authorization', 'Bearer ' + sessionId);
rp.setHeader('Content-Type', 'application/json');
rp.setBody('{"DeveloperName":"QuoteToCntrPersistenceMapping_plain","MasterLabel":"QuoteToCntrPersistenceMapping","ReferenceObjectName":"Quote","TargetObjectName":"Contract","TargetObjectCustomFieldName":"SourceQuoteId","ContextDefinitionName":"ContractsContextDefinition__stdctx","MappingName":"QuoteToCntrPersistenceMapping","MappingType":"Persistence","UseCaseType":"ContractCreationOrUpdation"}');
System.debug('per plain: ' + http.send(rp).getBody());

// 3. Test createClmContract on a quote
Invocable.Action action = Invocable.Action.createStandardAction('createClmContract');
action.setInvocationParameter('sourceRecordId', '0Q0aj000002CmqvCAC');
List<Invocable.Action.Result> results = action.invoke();
for (Invocable.Action.Result r : results) {
    if (r.isSuccess()) System.debug('SUCCESS contractId=' + r.getOutputParameters().get('contractId'));
    else System.debug('FAIL: ' + JSON.serialize(r.getErrors()));
}