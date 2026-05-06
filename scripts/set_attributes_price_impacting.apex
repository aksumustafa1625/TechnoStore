// Set IsPriceImpacting=true on all ProductAttributeDefinition records for Storage, Processor,
// and Screen Size attributes — required before AttributeAdjustmentCondition can be inserted.

Set<Id> attrDefIds = new Set<Id>{
    '0tjaj000000FbXNAA0', // Storage
    '0tjaj000000FbXMAA0', // Processor
    '0tjaj000000FbXHAA0'  // Screen Size
};

List<ProductAttributeDefinition> pads = [
    SELECT Id, AttributeDefinitionId, IsPriceImpacting
    FROM ProductAttributeDefinition
    WHERE AttributeDefinitionId IN :attrDefIds AND IsPriceImpacting = false
];
System.debug('Found ' + pads.size() + ' PADs to update');
for (ProductAttributeDefinition p : pads) p.IsPriceImpacting = true;
update pads;
System.debug('Updated ' + pads.size() + ' PADs to IsPriceImpacting=true');
