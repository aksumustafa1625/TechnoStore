// Find products that are SAFE to delete:
//   - No QuoteLineItem references (not in active quotes)
//   - No OrderItem references (not in orders)
//   - Not in critical demo product code list
//
// Products explicitly PROTECTED (never delete):
Set<String> protectedCodes = new Set<String>{
    // Workstations
    'COMP-WS-001','COMP-WS-002','COMP-WS-PREMIUM','COMP-WS-STUDIO',
    'COMP-WS-OFFICE','COMP-WS-BUSINESS','COMP-WS-HYPERSCALE',
    // Laptops (popular demo)
    'COMP-LAP-001','COMP-LAP-002','COMP-LAP-003','COMP-LAP-004','COMP-LAP-005',
    // POS demo
    'POS01','ENPOS101','REG01','SCN01',
    // Spring Sale 2026 promo
    'BUNDLE-GAMING-001','GAM-VR-001','AV-MON-004',
    // Common bundles likely used in demos
    'BUNDLE-LAPTOPPRO','BUNDLE-SMARTHOME-001','LPB001',
    // Inventory approval demo
    'H001'
};

// Find products with no Quote/Order line item references
Set<Id> productsInUse = new Set<Id>();
for (QuoteLineItem qli : [SELECT Product2Id FROM QuoteLineItem WHERE Product2Id != null LIMIT 1000]) productsInUse.add(qli.Product2Id);
for (OrderItem oi : [SELECT Product2Id FROM OrderItem WHERE Product2Id != null LIMIT 1000]) productsInUse.add(oi.Product2Id);
System.debug('Products with active references: ' + productsInUse.size());

// Get all active products that are NOT protected and NOT in use
List<Product2> candidates = [
    SELECT Id, Name, ProductCode, Family, Type, Description
    FROM Product2
    WHERE IsActive = true
      AND ProductCode NOT IN :protectedCodes
      AND Id NOT IN :productsInUse
    ORDER BY Name
];
System.debug('Total deletion candidates: ' + candidates.size());

System.debug('======== Candidates by Family/Type ========');
Map<String, Integer> byFamily = new Map<String, Integer>();
for (Product2 p : candidates) {
    String key = (p.Family == null ? 'null' : p.Family);
    byFamily.put(key, (byFamily.containsKey(key) ? byFamily.get(key) : 0) + 1);
}
for (String k : byFamily.keySet()) System.debug('  ' + k + ': ' + byFamily.get(k));

System.debug('======== First 60 candidates (alphabetical) ========');
Integer i = 0;
for (Product2 p : candidates) {
    if (i >= 60) break;
    System.debug('  ' + (++i) + '. ' + p.Name.rightPad(40) + ' | ' + (p.ProductCode == null ? 'NO_CODE' : p.ProductCode).rightPad(20) + ' | Family=' + p.Family);
}
