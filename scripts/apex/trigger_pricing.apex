String quoteId = [SELECT Id FROM Quote WHERE QuoteNumber = '00000075' LIMIT 1].Id;
System.debug('Quote: ' + quoteId);

Http http = new Http();
HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v63.0/actions/standard/runSalesforcePricing');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');

Map<String, Object> body = new Map<String, Object>{
    'inputs' => new List<Object>{
        new Map<String, Object>{
            'transactionId' => quoteId,
            'pricingOperationType' => 'PRICING_AND_TAX'
        }
    }
};
req.setBody(JSON.serialize(body));

HttpResponse res = http.send(req);
System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody());
