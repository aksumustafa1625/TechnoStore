// Directly call the tax calc REST endpoint
Id quoteId = [SELECT Id FROM Quote WHERE QuoteNumber = '00000075' LIMIT 1].Id;
System.debug('Quote: ' + quoteId);

HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v63.0/commerce/revenue/tax/calculate-tax');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');

Map<String, Object> body = new Map<String, Object>{
    'transactionId' => quoteId
};
req.setBody(JSON.serialize(body));

HttpResponse res = new Http().send(req);
System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody().left(3000));
