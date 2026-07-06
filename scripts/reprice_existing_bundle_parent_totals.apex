Set<Id> quoteIds = new Set<Id>{
    '0Q0aj000002hDwyCAE', // Demo Quote 4
    '0Q0aj000002hDwzCAE'  // Demo Quote 5
};

Map<String, List<List<String>>> parentDefaultsByProductCode = new Map<String, List<List<String>>>();
parentDefaultsByProductCode.put('BUNDLE-OFFICE-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch'}
});
parentDefaultsByProductCode.put('BUNDLE-CREATOR-001', new List<List<String>>{
    new List<String>{'0tjaj000000FbXJAA0', '0v6aj000000G24WAAS', 'RAM 16GB'},
    new List<String>{'0tjaj000000FbXNAA0', '0v6aj000000G24iAAC', 'SSD Hard Drive 512GB'},
    new List<String>{'0tjaj000000FbXMAA0', '0v6aj000000G24cAAC', 'i7-CPU 4.7GHz'},
    new List<String>{'0tjaj000000FbXHAA0', '0v6aj000000G24RAAS', '15 Inch'}
});

List<QuoteLineItem> parentLines = [
    SELECT Id, QuoteId, Product2.Name, Product2.ProductCode, Quantity,
           PricebookEntry.UnitPrice, UnitPrice
    FROM QuoteLineItem
    WHERE QuoteId IN :quoteIds
      AND Product2.ProductCode IN :parentDefaultsByProductCode.keySet()
];

Set<Id> parentLineIds = new Set<Id>();
for (QuoteLineItem parentLine : parentLines) {
    parentLineIds.add(parentLine.Id);
}

Map<Id, List<QuoteLineItemAttribute>> existingAttrsByLine = new Map<Id, List<QuoteLineItemAttribute>>();
List<QuoteLineItemAttribute> attrsToDelete = new List<QuoteLineItemAttribute>();
if (!parentLineIds.isEmpty()) {
    attrsToDelete = [
        SELECT Id, QuoteLineItemId, AttributeDefinitionId, AttributePicklistValueId, AttributeValue
        FROM QuoteLineItemAttribute
        WHERE QuoteLineItemId IN :parentLineIds
    ];
    for (QuoteLineItemAttribute attr : attrsToDelete) {
        if (!existingAttrsByLine.containsKey(attr.QuoteLineItemId)) {
            existingAttrsByLine.put(attr.QuoteLineItemId, new List<QuoteLineItemAttribute>());
        }
        existingAttrsByLine.get(attr.QuoteLineItemId).add(attr);
    }
}

if (!attrsToDelete.isEmpty()) {
    Database.deleteImmediate(attrsToDelete);
}

String resetToken = 'Bundle price reset ' + String.valueOf(DateTime.now().getTime());
List<QuoteLineItem> resetLines = new List<QuoteLineItem>();
for (QuoteLineItem parentLine : parentLines) {
    resetLines.add(new QuoteLineItem(
        Id = parentLine.Id,
        UnitPrice = parentLine.PricebookEntry.UnitPrice,
        Description = resetToken
    ));
}
if (!resetLines.isEmpty()) {
    update resetLines;
}

List<QuoteLineItemAttribute> attrsToInsert = new List<QuoteLineItemAttribute>();
for (QuoteLineItem parentLine : parentLines) {
    List<QuoteLineItemAttribute> existingAttrs = existingAttrsByLine.get(parentLine.Id);
    if (existingAttrs != null && !existingAttrs.isEmpty()) {
        for (QuoteLineItemAttribute existing : existingAttrs) {
            attrsToInsert.add(new QuoteLineItemAttribute(
                QuoteLineItemId = parentLine.Id,
                AttributeDefinitionId = existing.AttributeDefinitionId,
                AttributePicklistValueId = existing.AttributePicklistValueId,
                AttributeValue = existing.AttributeValue,
                ExternalId = 'reprice-restore-' + String.valueOf(parentLine.Id) + '-' + String.valueOf(existing.AttributeDefinitionId)
            ));
        }
        continue;
    }

    String productCode = parentLine.Product2 != null ? parentLine.Product2.ProductCode : null;
    List<List<String>> defaultSpecs = parentDefaultsByProductCode.get(productCode);
    if (defaultSpecs == null) continue;
    for (List<String> spec : defaultSpecs) {
        attrsToInsert.add(new QuoteLineItemAttribute(
            QuoteLineItemId = parentLine.Id,
            AttributeDefinitionId = spec[0],
            AttributePicklistValueId = spec[1],
            AttributeValue = spec[2],
            ExternalId = 'reprice-default-' + String.valueOf(parentLine.Id) + '-' + spec[0]
        ));
    }
}

if (!attrsToInsert.isEmpty()) {
    Database.insertImmediate(attrsToInsert);
}

List<QuoteLineItem> refreshLines = new List<QuoteLineItem>();
for (QuoteLineItem parentLine : parentLines) {
    String productName = parentLine.Product2 != null ? parentLine.Product2.Name : 'Bundle';
    refreshLines.add(new QuoteLineItem(
        Id = parentLine.Id,
        Description = productName
    ));
}
if (!refreshLines.isEmpty()) {
    update refreshLines;
}

System.debug('REPRICE_PARENT_LINES=' + parentLines.size());
System.debug('REPRICE_PARENT_ATTRS_DELETED=' + attrsToDelete.size());
System.debug('REPRICE_PARENT_ATTRS_REINSERTED=' + attrsToInsert.size());
