// PHASE 1: Create AttributePicklists + Values, then activate
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

List<AttributePicklist> picklistsToInsert = new List<AttributePicklist>();
Map<String, Integer> attrIndex = new Map<String, Integer>();

for (String className : spec.keySet()) {
    for (String attrName : spec.get(className).keySet()) {
        AttributePicklist pl = new AttributePicklist();
        pl.Name = attrName + ' Picklist';
        pl.Code = className.replace(' ', '_') + '_' + attrName.replace(' ', '_');
        attrIndex.put(className + '|' + attrName, picklistsToInsert.size());
        picklistsToInsert.add(pl);
    }
}
insert picklistsToInsert;
System.debug('STEP 1: Inserted ' + picklistsToInsert.size() + ' AttributePicklists');

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
insert valuesToInsert;
System.debug('STEP 2: Inserted ' + valuesToInsert.size() + ' AttributePicklistValues');

// Activate all picklists
List<AttributePicklist> toActivate = new List<AttributePicklist>();
for (AttributePicklist pl : picklistsToInsert) {
    toActivate.add(new AttributePicklist(Id = pl.Id, Status = 'Active'));
}
update toActivate;
System.debug('STEP 3: Updated ' + toActivate.size() + ' AttributePicklists to Active');

System.debug('PHASE 1 COMPLETE — verify with query, then run phase 2');
