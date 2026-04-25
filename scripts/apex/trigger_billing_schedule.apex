// Trigger createBillingSchedulesFromBillingTransaction for Order 152
String orderId = '801aj00002hVedhAAC';

HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v63.0/actions/standard/createBillingSchedulesFromBillingTransaction');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');

Map<String, Object> body = new Map<String, Object>{
    'inputs' => new List<Object>{
        new Map<String, Object>{
            'billingTransactionId' => orderId
        }
    }
};
req.setBody(JSON.serialize(body));
req.setTimeout(120000);

HttpResponse res = new Http().send(req);
System.debug('=STATUS=' + res.getStatusCode());
System.debug('=BODY=' + res.getBody());
