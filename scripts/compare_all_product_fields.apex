// Exhaustive field comparison: list every populated field on my Premium Workstation Pro
// vs WorkStation X Pro vs RenderStation Ultra. Find the missing field that prevents
// catalog visibility.

List<String> codes = new List<String>{'COMP-WS-PREMIUM','COMP-WS-001'};
Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Product2.fields.getMap();
String soql = 'SELECT ';
List<String> fieldNames = new List<String>();
for (String fn : fieldMap.keySet()) {
    Schema.DescribeFieldResult d = fieldMap.get(fn).getDescribe();
    if (d.isAccessible() && d.getType() != Schema.DisplayType.ADDRESS) {
        fieldNames.add(fn);
    }
}
soql += String.join(fieldNames, ',') + ' FROM Product2 WHERE ProductCode IN :codes';

List<Product2> products = Database.query(soql);
Map<String, Product2> byCode = new Map<String, Product2>();
for (Product2 p : products) byCode.put(p.ProductCode, p);

System.debug('======== Field-by-field diff ========');
Product2 a = byCode.get('COMP-WS-PREMIUM');
Product2 b = byCode.get('COMP-WS-001');
if (a == null || b == null) {
    System.debug('Missing one of the products');
    return;
}
for (String fn : fieldNames) {
    Object av = a.get(fn);
    Object bv = b.get(fn);
    String avStr = av == null ? 'null' : String.valueOf(av);
    String bvStr = bv == null ? 'null' : String.valueOf(bv);
    if (avStr != bvStr) {
        System.debug('  DIFF: ' + fn.rightPad(40) + ' | Premium=' + avStr + ' | WorkStation X Pro=' + bvStr);
    }
}
