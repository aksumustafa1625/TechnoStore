Http http = new Http();
String baseUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();

HttpRequest req = new HttpRequest();
req.setEndpoint(baseUrl + '/services/data/v63.0/actions/standard');
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + sessionId);
HttpResponse res = http.send(req);
Map<String,Object> j = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
List<Object> actions = (List<Object>) j.get('actions');
for (Object a : actions) {
    Map<String,Object> am = (Map<String,Object>) a;
    String name = (String) am.get('name');
    String label = (String) am.get('label');
    if (name != null && (name.toLowerCase().contains('contract') || name.toLowerCase().contains('context'))) {
        System.debug(name + ' | ' + label);
    }
}