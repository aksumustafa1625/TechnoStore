Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

// 1. Set Quote and Order line Name mappings back to Description
for (String mapId : new List<String>{'11Raj000007hbE1EAI','11Raj000007hbDaEAI'}) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + '/services/data/v63.0/sobjects/ContextAttributeMapping/' + mapId);
    req.setMethod('PATCH');
    req.setHeader('Authorization', 'Bearer ' + sessionId);
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"ContextInputAttributeName":"Description"}');
    System.debug('patch ' + mapId + ' => ' + http.send(req).getStatusCode());
}

// 2. Backfill Description on all existing QLIs and OrderItems that have it null
List<QuoteLineItem> qlisToFix = [SELECT Id, Description, Product2.Name, LineNumber FROM QuoteLineItem WHERE Description = null];
for (QuoteLineItem q : qlisToFix) q.Description = q.Product2 != null ? q.Product2.Name : ('Line ' + q.LineNumber);
if (!qlisToFix.isEmpty()) update qlisToFix;
System.debug('Updated QLIs: ' + qlisToFix.size());

List<OrderItem> oisToFix = [SELECT Id, Description, Product2.Name FROM OrderItem WHERE Description = null];
for (OrderItem oi : oisToFix) oi.Description = oi.Product2 != null ? oi.Product2.Name : 'Line Item';
if (!oisToFix.isEmpty()) update oisToFix;
System.debug('Updated OrderItems: ' + oisToFix.size());