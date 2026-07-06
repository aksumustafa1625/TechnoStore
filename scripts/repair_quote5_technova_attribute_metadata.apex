Id techNovaId = '01taj00000QnnlNAAR';
Map<String, Id> attrDefByName = new Map<String, Id>{
    'Memory' => '0tjaj000000FbXJAA0',
    'Storage' => '0tjaj000000FbXNAA0',
    'Processor' => '0tjaj000000FbXMAA0',
    'Graphics' => '0tjaj000000FbXIAA0',
    'Screen Size' => '0tjaj000000FbXHAA0'
};

Map<String, Id> classAttrByName = new Map<String, Id>{
    'Memory' => '11Caj00003zgbBNEAY',
    'Storage' => '11Caj00003zgbBOEAY',
    'Processor' => '11Caj00003zgbBPEAY',
    'Graphics' => '11Caj00003zgbBQEAY',
    'Screen Size' => '11Caj00003zgbBREAY'
};

Map<String, Integer> sequenceByName = new Map<String, Integer>{
    'Memory' => 1,
    'Storage' => 2,
    'Processor' => 3,
    'Graphics' => 4,
    'Screen Size' => 5
};

Map<Id, ProductAttributeDefinition> existingByAttrDef = new Map<Id, ProductAttributeDefinition>();
for (ProductAttributeDefinition pad : [
    SELECT Id, Name, AttributeDefinitionId, IsPriceImpacting, Sequence, Status,
           ProductClassificationAttributeId
    FROM ProductAttributeDefinition
    WHERE Product2Id = :techNovaId
]) {
    existingByAttrDef.put(pad.AttributeDefinitionId, pad);
}

List<ProductAttributeDefinition> toInsert = new List<ProductAttributeDefinition>();
List<ProductAttributeDefinition> toUpdate = new List<ProductAttributeDefinition>();

for (String attrName : new List<String>{'Memory', 'Storage', 'Processor', 'Graphics', 'Screen Size'}) {
    Id attrDefId = attrDefByName.get(attrName);
    ProductAttributeDefinition pad = existingByAttrDef.get(attrDefId);

    if (pad == null) {
        toInsert.add(new ProductAttributeDefinition(
            Name = 'TechNova ProBook 15-' + attrName,
            Product2Id = techNovaId,
            AttributeDefinitionId = attrDefId,
            ProductClassificationAttributeId = classAttrByName.get(attrName),
            Status = 'Active',
            IsRequired = false,
            IsHidden = false,
            IsReadOnly = false,
            IsPriceImpacting = attrName != 'Graphics',
            Sequence = sequenceByName.get(attrName)
        ));
    } else {
        Boolean changed = false;
        if (pad.Status != 'Active') {
            pad.Status = 'Active';
            changed = true;
        }
        if (pad.ProductClassificationAttributeId == null) {
            pad.ProductClassificationAttributeId = classAttrByName.get(attrName);
            changed = true;
        }
        Boolean shouldBePriceImpacting = attrName != 'Graphics';
        if (pad.IsPriceImpacting != shouldBePriceImpacting) {
            pad.IsPriceImpacting = shouldBePriceImpacting;
            changed = true;
        }
        Integer expectedSequence = sequenceByName.get(attrName);
        if (pad.Sequence != expectedSequence) {
            pad.Sequence = expectedSequence;
            changed = true;
        }
        if (changed) {
            toUpdate.add(pad);
        }
    }
}

if (!toInsert.isEmpty()) {
    insert toInsert;
}
if (!toUpdate.isEmpty()) {
    update toUpdate;
}

System.debug('Inserted ProductAttributeDefinition count: ' + toInsert.size());
System.debug('Updated ProductAttributeDefinition count: ' + toUpdate.size());
