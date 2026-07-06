Set<Id> quoteIds = new Set<Id>{
    '0Q0aj000002hDwyCAE', // Demo Quote 4
    '0Q0aj000002hDwzCAE'  // Demo Quote 5
};

Map<String, List<List<String>>> defaultsByProductCode = new Map<String, List<List<String>>>();

defaultsByProductCode.put('BUNDLE-OFFICE-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch'}
});

defaultsByProductCode.put('BUNDLE-CREATOR-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch'}
});

defaultsByProductCode.put('COMP-LAP-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch'}
});

defaultsByProductCode.put('COMP-LAP-003', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24XAAS', 'RAM 8GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24hAAC', 'SSD Hard Drive 256GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24eAAC', 'i5-CPU 4.4GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24PAAS', '13 Inch'}
});

defaultsByProductCode.put('AV-MON-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXFAA0', '0v6aj000000G24KAAS', '2k Built-in Display'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24OAAS', '27 Inch'}
});

defaultsByProductCode.put('SVC-WAR-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXBAA0', '0v6aj000000G251AAC', 'Business'}
});

List<QuoteLineItem> qlis = [
    SELECT Id, QuoteId, Product2.Name, Product2.ProductCode, Product2.Type, Quantity
    FROM QuoteLineItem
    WHERE QuoteId IN :quoteIds
      AND Product2.ProductCode IN :defaultsByProductCode.keySet()
];

Set<Id> qliIds = new Set<Id>();
for (QuoteLineItem qli : qlis) {
    qliIds.add(qli.Id);
}

Set<String> existingKeys = new Set<String>();
if (!qliIds.isEmpty()) {
    for (QuoteLineItemAttribute existing : [
        SELECT QuoteLineItemId, AttributeDefinitionId
        FROM QuoteLineItemAttribute
        WHERE QuoteLineItemId IN :qliIds
    ]) {
        existingKeys.add(String.valueOf(existing.QuoteLineItemId) + '|' + String.valueOf(existing.AttributeDefinitionId));
    }
}

List<QuoteLineItemAttribute> attrsToInsert = new List<QuoteLineItemAttribute>();
List<QuoteLineItem> bundleLinesToRefresh = new List<QuoteLineItem>();
List<QuoteLineItem> bundleLinesToClean = new List<QuoteLineItem>();
String refreshToken = 'Bundle price refresh ' + String.valueOf(DateTime.now().getTime());

for (QuoteLineItem qli : qlis) {
    String productCode = qli.Product2 != null ? qli.Product2.ProductCode : null;
    List<List<String>> defaults = defaultsByProductCode.get(productCode);
    if (defaults == null) continue;

    if (productCode == 'BUNDLE-OFFICE-001' || productCode == 'BUNDLE-CREATOR-001') {
        String productName = qli.Product2 != null ? qli.Product2.Name : productCode;
        bundleLinesToRefresh.add(new QuoteLineItem(
            Id = qli.Id,
            Description = refreshToken
        ));
        bundleLinesToClean.add(new QuoteLineItem(
            Id = qli.Id,
            Description = productName
        ));
    }

    for (List<String> spec : defaults) {
        String attributeDefinitionId = spec[0];
        String attributePicklistValueId = spec[1];
        String attributeValue = spec[2];
        String key = String.valueOf(qli.Id) + '|' + attributeDefinitionId;
        if (existingKeys.contains(key)) continue;

        attrsToInsert.add(new QuoteLineItemAttribute(
            QuoteLineItemId = qli.Id,
            AttributeDefinitionId = attributeDefinitionId,
            AttributePicklistValueId = attributePicklistValueId,
            AttributeValue = attributeValue,
            ExternalId = 'repair-default-' + String.valueOf(qli.Id) + '-' + attributeDefinitionId
        ));
        existingKeys.add(key);
    }
}

if (!attrsToInsert.isEmpty()) {
    Database.insertImmediate(attrsToInsert);
}

if (!bundleLinesToRefresh.isEmpty()) {
    update bundleLinesToRefresh;
    update bundleLinesToClean;
}

System.debug('REPAIR_ATTRS_INSERTED=' + attrsToInsert.size());
System.debug('REPAIR_BUNDLE_LINES_TOUCHED=' + bundleLinesToRefresh.size());
