// =====================================================
// Create attributes for 4 bundle component classifications
// =====================================================
// External Monitor (Monitor 24" IPS)  : 11Baj000015O78GEAS
// Keyboard         (Wireless Combo Set): 11Baj000014WD4LEAW
// Software         (MS 365 Personal)   : 11Baj000014WD4AEAW
// Warranty Service (TechCover 1 Yıl)   : 11Baj000015O78KEAS

Map<String, Id> classMap = new Map<String, Id>{
    'External Monitor' => '11Baj000015O78GEAS',
    'Keyboard'         => '11Baj000014WD4LEAW',
    'Software'         => '11Baj000014WD4AEAW',
    'Warranty Service' => '11Baj000015O78KEAS'
};

// Attribute spec: classification -> attribute name -> picklist values list
Map<String, Map<String, List<String>>> spec = new Map<String, Map<String, List<String>>>{
    'External Monitor' => new Map<String, List<String>>{
        'Resolution'   => new List<String>{'Full HD', 'QHD', '4K UHD'},
        'Refresh Rate' => new List<String>{'60Hz', '120Hz', '144Hz'}
    },
    'Keyboard' => new Map<String, List<String>>{
        'Color'  => new List<String>{'Black', 'White', 'Silver'},
        'Layout' => new List<String>{'Turkish Q', 'English US', 'German'}
    },
    'Software' => new Map<String, List<String>>{
        'Plan Tier'           => new List<String>{'Personal', 'Family'},
        'Subscription Period' => new List<String>{'Annual', 'Monthly'}
    },
    'Warranty Service' => new Map<String, List<String>>{
        'Coverage Level' => new List<String>{'Standard', 'Premium', 'Platinum'},
        'Service Term'   => new List<String>{'1 Year', '2 Years', '3 Years'}
    }
};

// =====================================================
// Step 1: Create AttributePicklists (one per attribute)
// =====================================================
List<AttributePicklist> picklistsToInsert = new List<AttributePicklist>();
Map<String, Integer> attrIndex = new Map<String, Integer>(); // attrName -> picklist index

for (String className : spec.keySet()) {
    for (String attrName : spec.get(className).keySet()) {
        AttributePicklist pl = new AttributePicklist();
        pl.Name = attrName + ' Picklist';
        pl.Code = className.replace(' ', '_') + '_' + attrName.replace(' ', '_');
        attrIndex.put(className + '|' + attrName, picklistsToInsert.size());
        picklistsToInsert.add(pl);
    }
}
try {
    insert picklistsToInsert;
    System.debug('STEP 1 OK: Inserted ' + picklistsToInsert.size() + ' AttributePicklists');
} catch (Exception e) {
    System.debug('STEP 1 FAILED (AttributePicklist): ' + e.getMessage());
    throw e;
}

// =====================================================
// Step 2: Create AttributePicklistValues
// =====================================================
List<AttributePicklistValue> valuesToInsert = new List<AttributePicklistValue>();

for (String className : spec.keySet()) {
    for (String attrName : spec.get(className).keySet()) {
        Integer idx = attrIndex.get(className + '|' + attrName);
        Id picklistId = picklistsToInsert[idx].Id;
        Integer seq = 1;
        for (String v : spec.get(className).get(attrName)) {
            valuesToInsert.add(new AttributePicklistValue(
                PicklistId = picklistId,
                Name = v,
                Value = v,
                Code = v,
                Status = 'Active',
                Sequence = seq++
            ));
        }
    }
}
try {
    insert valuesToInsert;
    System.debug('STEP 2 OK: Inserted ' + valuesToInsert.size() + ' AttributePicklistValues');
} catch (Exception e) {
    System.debug('STEP 2 FAILED (AttributePicklistValue): ' + e.getMessage());
    throw e;
}

// Step 2.5: Activate picklists now that they have values
List<AttributePicklist> toActivate = new List<AttributePicklist>();
for (AttributePicklist pl : picklistsToInsert) {
    toActivate.add(new AttributePicklist(Id = pl.Id, Status = 'Active'));
}
try {
    update toActivate;
    System.debug('STEP 2.5 OK: Activated ' + toActivate.size() + ' AttributePicklists');
} catch (Exception e) {
    System.debug('STEP 2.5 FAILED (Activate Picklist): ' + e.getMessage());
    throw e;
}

// =====================================================
// Step 3: Create AttributeDefinitions
// =====================================================
List<AttributeDefinition> defsToInsert = new List<AttributeDefinition>();
Map<String, Integer> defIndex = new Map<String, Integer>();

for (String className : spec.keySet()) {
    for (String attrName : spec.get(className).keySet()) {
        Integer idx = attrIndex.get(className + '|' + attrName);
        Id picklistId = picklistsToInsert[idx].Id;
        String devName = className.replace(' ', '_') + '_' + attrName.replace(' ', '_');
        defIndex.put(className + '|' + attrName, defsToInsert.size());
        defsToInsert.add(new AttributeDefinition(
            Name = attrName,
            Code = devName,
            DeveloperName = devName,
            Label = attrName,
            DataType = 'Picklist',
            PicklistId = picklistId,
            IsActive = true
        ));
    }
}
try {
    insert defsToInsert;
    System.debug('STEP 3 OK: Inserted ' + defsToInsert.size() + ' AttributeDefinitions');
} catch (Exception e) {
    System.debug('STEP 3 FAILED (AttributeDefinition): ' + e.getMessage());
    throw e;
}

// =====================================================
// Step 4: Link AttributeDefinitions to Classifications
// =====================================================
List<ProductClassificationAttr> linksToInsert = new List<ProductClassificationAttr>();

for (String className : spec.keySet()) {
    Id classId = classMap.get(className);
    for (String attrName : spec.get(className).keySet()) {
        Integer idx = defIndex.get(className + '|' + attrName);
        Id defId = defsToInsert[idx].Id;
        linksToInsert.add(new ProductClassificationAttr(
            ProductClassificationId = classId,
            AttributeDefinitionId = defId
        ));
    }
}
try {
    insert linksToInsert;
    System.debug('STEP 4 OK: Inserted ' + linksToInsert.size() + ' ProductClassificationAttrs');
} catch (Exception e) {
    System.debug('STEP 4 FAILED (ProductClassificationAttr): ' + e.getMessage());
    throw e;
}

System.debug('=== BUNDLE ATTRIBUTES SETUP COMPLETE ===');
System.debug('4 classifications now have attributes attached.');
System.debug('Test by going to Quote → Add Home Office Bundle → Configure → should see 5 tabs/sections');
