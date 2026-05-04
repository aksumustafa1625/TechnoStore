// Activate all attribute pricing schedules for future demo flexibility
List<PriceAdjustmentSchedule> schedules = [
    SELECT Id, Name, IsActive, ScheduleType FROM PriceAdjustmentSchedule
    WHERE ScheduleType='Attribute' AND IsActive=false
];
for (PriceAdjustmentSchedule s : schedules) s.IsActive = true;
update schedules;
for (PriceAdjustmentSchedule s : schedules) System.debug('Activated: ' + s.Name);

// Also verify ProductAttributeDefinition structure - what fields link Product to Attribute?
Schema.DescribeSObjectResult d = Schema.SObjectType.ProductAttributeDefinition;
Map<String, Schema.SObjectField> fields = d.fields.getMap();
System.debug('--- ProductAttributeDefinition fields ---');
for (String fn : fields.keySet()) {
    Schema.DescribeFieldResult f = fields.get(fn).getDescribe();
    if (f.getType() == Schema.DisplayType.REFERENCE && !f.isDeprecatedAndHidden()) {
        System.debug(f.getName() + ' -> ' + f.getReferenceTo());
    }
}

// Query existing PADs related to bundle/laptop
System.debug('--- Existing PADs (sample) ---');
for (ProductAttributeDefinition pad : [SELECT FIELDS(STANDARD) FROM ProductAttributeDefinition LIMIT 5]) {
    System.debug(pad);
}
