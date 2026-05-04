// Create ProductAttributeDefinition record for Home Office Bundle linking to RAM attribute
// This makes the engine recognize RAM as price-impacting for this bundle

Id bundleId = '01taj00000Qp7IFAAZ';
Id ramAttrId = '0tjaj000000FbXJAA0';
Id classificationAttrId = '11Caj00003zgbBNEAY'; // From other bundles' PAD records

ProductAttributeDefinition pad = new ProductAttributeDefinition(
    Name = 'Home Office Bundle-Memory',
    Product2Id = bundleId,
    AttributeDefinitionId = ramAttrId,
    ProductClassificationAttributeId = classificationAttrId,
    IsHidden = false,
    IsReadOnly = false,
    IsRequired = false,
    Status = 'Active',
    IsPriceImpacting = true,
    Sequence = 1
);
insert pad;
System.debug('Created PAD: ' + pad.Id);

// Verify
for (ProductAttributeDefinition p : [
    SELECT Id, Name, AttributeDefinitionId, IsPriceImpacting, Status
    FROM ProductAttributeDefinition WHERE Product2Id=:bundleId
]) {
    System.debug(p.Name + ' attr=' + p.AttributeDefinitionId + ' priceImpact=' + p.IsPriceImpacting + ' status=' + p.Status);
}
