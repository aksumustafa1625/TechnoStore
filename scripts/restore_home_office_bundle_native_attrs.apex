// Restore native RLM ProductAttributeDefinition mappings for Home Office Bundle.
// Idempotent: inserts only missing mappings and leaves existing ones untouched.

Id bundleId = '01taj00000Qp7IFAAZ'; // Home Office Bundle

List<Product2> bundles = [
    SELECT Id, Name, ProductCode, BasedOnId, BasedOn.Name
    FROM Product2
    WHERE Id = :bundleId
    LIMIT 1
];
if (bundles.isEmpty()) {
    throw new AuraHandledException('Home Office Bundle product was not found: ' + bundleId);
}
Product2 bundle = bundles[0];
if (bundle.BasedOnId == null) {
    throw new AuraHandledException('Home Office Bundle has no BasedOn classification.');
}

Map<String, Id> attrDefByName = new Map<String, Id>{
    'Memory' => '0tjaj000000FbXJAA0',
    'Storage' => '0tjaj000000FbXNAA0',
    'Processor' => '0tjaj000000FbXMAA0',
    'Screen Size' => '0tjaj000000FbXHAA0'
};

Map<Id, ProductClassificationAttr> classAttrByDefId = new Map<Id, ProductClassificationAttr>();
for (ProductClassificationAttr pca : [
    SELECT Id, AttributeDefinitionId, Sequence
    FROM ProductClassificationAttr
    WHERE ProductClassificationId = :bundle.BasedOnId
    AND AttributeDefinitionId IN :attrDefByName.values()
]) {
    classAttrByDefId.put(pca.AttributeDefinitionId, pca);
}

Set<Id> existingAttrDefIds = new Set<Id>();
for (ProductAttributeDefinition pad : [
    SELECT Id, AttributeDefinitionId
    FROM ProductAttributeDefinition
    WHERE Product2Id = :bundleId
    AND AttributeDefinitionId IN :attrDefByName.values()
]) {
    existingAttrDefIds.add(pad.AttributeDefinitionId);
}

List<ProductAttributeDefinition> padsToInsert = new List<ProductAttributeDefinition>();
for (String attrName : new List<String>{'Memory', 'Storage', 'Processor', 'Screen Size'}) {
    Id attrDefId = attrDefByName.get(attrName);
    if (existingAttrDefIds.contains(attrDefId)) continue;

    ProductClassificationAttr pca = classAttrByDefId.get(attrDefId);
    if (pca == null) {
        throw new AuraHandledException('Missing ProductClassificationAttr for ' + attrName + ' on classification ' + bundle.BasedOnId);
    }

    padsToInsert.add(new ProductAttributeDefinition(
        Name = 'Home Office Bundle-' + attrName,
        Product2Id = bundleId,
        AttributeDefinitionId = attrDefId,
        ProductClassificationAttributeId = pca.Id,
        IsRequired = false,
        IsHidden = false,
        IsReadOnly = false,
        IsPriceImpacting = (attrName == 'Memory'),
        Status = 'Active',
        Sequence = pca.Sequence
    ));
}

if (!padsToInsert.isEmpty()) {
    insert padsToInsert;
}

System.debug('Home Office Bundle: ' + bundle.Name + ' / ' + bundle.ProductCode);
System.debug('BasedOn: ' + bundle.BasedOn.Name + ' (' + bundle.BasedOnId + ')');
System.debug('Inserted ProductAttributeDefinition count: ' + padsToInsert.size());

for (ProductAttributeDefinition pad : [
    SELECT Id, Name, AttributeDefinition.Name, ProductClassificationAttributeId,
           IsRequired, IsHidden, IsReadOnly, IsPriceImpacting, Status, Sequence
    FROM ProductAttributeDefinition
    WHERE Product2Id = :bundleId
    AND AttributeDefinitionId IN :attrDefByName.values()
    ORDER BY Sequence
]) {
    System.debug(
        pad.Name +
        ' attr=' + pad.AttributeDefinition.Name +
        ' pca=' + pad.ProductClassificationAttributeId +
        ' required=' + pad.IsRequired +
        ' priceImpacting=' + pad.IsPriceImpacting +
        ' status=' + pad.Status +
        ' seq=' + pad.Sequence
    );
}
