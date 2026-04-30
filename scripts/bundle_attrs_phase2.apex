// PHASE 2: Create AttributeDefinitions linked to active picklists, then ProductClassificationAttrs

Map<String, Id> classMap = new Map<String, Id>{
    'External Monitor' => '11Baj000015O78GEAS',
    'Keyboard'         => '11Baj000014WD4LEAW',
    'Software'         => '11Baj000014WD4AEAW',
    'Warranty Service' => '11Baj000015O78KEAS'
};

Map<String, AttributePicklist> picklistByCode = new Map<String, AttributePicklist>();
for (AttributePicklist pl : [
    SELECT Id, Code FROM AttributePicklist
    WHERE Code LIKE 'External_Monitor%' OR Code LIKE 'Keyboard%' OR Code LIKE 'Software%' OR Code LIKE 'Warranty_Service%'
]) {
    picklistByCode.put(pl.Code, pl);
}

Map<String, Map<String, String>> spec = new Map<String, Map<String, String>>{
    'External Monitor' => new Map<String, String>{
        'Resolution'   => 'External_Monitor_Resolution',
        'Refresh Rate' => 'External_Monitor_Refresh_Rate'
    },
    'Keyboard' => new Map<String, String>{
        'Color'  => 'Keyboard_Color',
        'Layout' => 'Keyboard_Layout'
    },
    'Software' => new Map<String, String>{
        'Plan Tier'           => 'Software_Plan_Tier',
        'Subscription Period' => 'Software_Subscription_Period'
    },
    'Warranty Service' => new Map<String, String>{
        'Coverage Level' => 'Warranty_Service_Coverage_Level',
        'Service Term'   => 'Warranty_Service_Service_Term'
    }
};

// Step 1: AttributeDefinitions
List<AttributeDefinition> defs = new List<AttributeDefinition>();
Map<String, Integer> defIndex = new Map<String, Integer>();

for (String className : spec.keySet()) {
    for (String attrName : spec.get(className).keySet()) {
        String picklistCode = spec.get(className).get(attrName);
        AttributePicklist pl = picklistByCode.get(picklistCode);
        if (pl == null) continue;
        defIndex.put(className + '|' + attrName, defs.size());
        defs.add(new AttributeDefinition(
            Name = attrName,
            Code = picklistCode,
            DeveloperName = picklistCode,
            Label = attrName,
            DataType = 'Picklist',
            PicklistId = pl.Id,
            IsActive = true,
            IsRequired = false
        ));
    }
}
insert defs;
System.debug('Inserted ' + defs.size() + ' AttributeDefinitions');

// Step 2: ProductClassificationAttrs (with required Name field)
List<ProductClassificationAttr> links = new List<ProductClassificationAttr>();
Integer seq = 1;
for (String className : spec.keySet()) {
    Id classId = classMap.get(className);
    Integer subSeq = 1;
    for (String attrName : spec.get(className).keySet()) {
        Integer idx = defIndex.get(className + '|' + attrName);
        if (idx == null) continue;
        Id defId = defs[idx].Id;
        links.add(new ProductClassificationAttr(
            Name = className + '-' + attrName,
            ProductClassificationId = classId,
            AttributeDefinitionId = defId,
            Status = 'Active',
            IsRequired = false,
            IsHidden = false,
            IsReadOnly = false,
            IsPriceImpacting = false,
            Sequence = subSeq++,
            AttributeNameOverride = attrName
        ));
    }
}
insert links;
System.debug('Inserted ' + links.size() + ' ProductClassificationAttrs');

System.debug('=== PHASE 2 COMPLETE ===');
