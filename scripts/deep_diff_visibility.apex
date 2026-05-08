// Deep diff: every related record between WorkStation X Pro (visible) and my new products (invisible)

Id workstationProId = '01taj00000QnnlaAAB';   // WorkStation X Pro (working)
Id premiumId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1].Id;
Id studioId  = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-WS-STUDIO'  LIMIT 1].Id;

System.debug('======== ProductCategoryProduct schema fields ========');
Map<String, Schema.SObjectField> pcpFields = Schema.SObjectType.ProductCategoryProduct.fields.getMap();
List<String> pcpFn = new List<String>();
for (String f : pcpFields.keySet()) {
    Schema.DescribeFieldResult d = pcpFields.get(f).getDescribe();
    if (d.getType() != Schema.DisplayType.ADDRESS) pcpFn.add(f);
}
String pcpSoql = 'SELECT ' + String.join(pcpFn, ',') + ' FROM ProductCategoryProduct WHERE ProductId IN (:workstationProId,:premiumId) LIMIT 10';
List<ProductCategoryProduct> pcps = Database.query(pcpSoql);
for (ProductCategoryProduct pcp : pcps) {
    System.debug('PCP: ProductId=' + pcp.ProductId + ' | CategoryId=' + pcp.ProductCategoryId);
    for (String f : pcpFn) {
        Object v = pcp.get(f);
        if (v != null) System.debug('  ' + f + ' = ' + v);
    }
    System.debug('  ----');
}

System.debug('======== Schema check: Product2 fields about visibility / specifications / availability ========');
for (String fn : new List<String>(Schema.SObjectType.Product2.fields.getMap().keySet())) {
    String lower = fn.toLowerCase();
    if (lower.contains('spec') || lower.contains('availab') || lower.contains('effective') || lower.contains('discover') || lower.contains('searchable') || lower.contains('visible')) {
        System.debug('  Product2.' + fn);
    }
}

System.debug('======== Product2 specs/availability values (visible vs my products) ========');
// Build dynamic SOQL with all simple fields
Map<String, Schema.SObjectField> p2 = Schema.SObjectType.Product2.fields.getMap();
List<String> simpleFields = new List<String>();
for (String f : p2.keySet()) {
    Schema.DescribeFieldResult d = p2.get(f).getDescribe();
    if (d.getType() != Schema.DisplayType.ADDRESS && d.getType() != Schema.DisplayType.LOCATION) {
        simpleFields.add(f);
    }
}
String soql = 'SELECT ' + String.join(simpleFields, ',') + ' FROM Product2 WHERE Id IN (:workstationProId,:premiumId,:studioId)';
List<Product2> p3 = Database.query(soql);
Product2 wsx = null;
Product2 prem = null;
Product2 studio = null;
for (Product2 p : p3) {
    if (p.Id == workstationProId) wsx = p;
    if (p.Id == premiumId) prem = p;
    if (p.Id == studioId) studio = p;
}
System.debug('======== Product2 ALL FIELDS — diff between visible (WSX) and invisible (Premium) ========');
for (String f : simpleFields) {
    Object wv = wsx == null ? null : wsx.get(f);
    Object pv = prem == null ? null : prem.get(f);
    String wvStr = wv == null ? 'null' : String.valueOf(wv);
    String pvStr = pv == null ? 'null' : String.valueOf(pv);
    if (wvStr != pvStr && f != 'id' && f != 'name' && f != 'productcode' && f != 'description' && f != 'createddate' && f != 'lastmodifieddate' && f != 'systemmodstamp' && f != 'lastvieweddate' && f != 'lastreferenceddate' && f != 'externalid' && f != 'stockkeepingunit') {
        System.debug('  DIFF ' + f + ' | WSX=' + wvStr + ' | Premium=' + pvStr);
    }
}
