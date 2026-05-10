// Continue from products 60 onwards

Set<String> protectedCodes = new Set<String>{
    'COMP-WS-001','COMP-WS-002','COMP-WS-PREMIUM','COMP-WS-STUDIO','COMP-WS-OFFICE','COMP-WS-BUSINESS','COMP-WS-HYPERSCALE',
    'COMP-LAP-001','COMP-LAP-002','COMP-LAP-003','COMP-LAP-004','COMP-LAP-005',
    'POS01','ENPOS101','REG01','SCN01',
    'BUNDLE-GAMING-001','GAM-VR-001','AV-MON-004',
    'BUNDLE-LAPTOPPRO','BUNDLE-SMARTHOME-001','LPB001','H001'
};

Set<Id> productsInUse = new Set<Id>();
for (QuoteLineItem qli : [SELECT Product2Id FROM QuoteLineItem WHERE Product2Id != null LIMIT 1000]) productsInUse.add(qli.Product2Id);
for (OrderItem oi : [SELECT Product2Id FROM OrderItem WHERE Product2Id != null LIMIT 1000]) productsInUse.add(oi.Product2Id);

List<Product2> candidates = [
    SELECT Id, Name, ProductCode, Family, Type
    FROM Product2
    WHERE IsActive = true AND ProductCode NOT IN :protectedCodes AND Id NOT IN :productsInUse
    ORDER BY Name
];

System.debug('======== Candidates 61-148 ========');
Integer i = 0;
for (Product2 p : candidates) {
    i++;
    if (i < 61) continue;
    System.debug('  ' + i + '. ' + p.Name.rightPad(40) + ' | ' + (p.ProductCode == null ? 'NO_CODE' : p.ProductCode).rightPad(20) + ' | Family=' + p.Family);
}
