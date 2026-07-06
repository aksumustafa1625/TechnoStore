Id techNovaId = '01taj00000QnnlNAAR';
Id scheduleId = '84Xaj000000I0SzEAK';
Datetime effectiveFrom = Datetime.newInstanceGmt(2026, 1, 1, 20, 0, 0);

Id memoryAttrId = '0tjaj000000FbXJAA0';
Id storageAttrId = '0tjaj000000FbXNAA0';
Id processorAttrId = '0tjaj000000FbXMAA0';
Id screenSizeAttrId = '0tjaj000000FbXHAA0';

Map<Id, String> selectedValuesByAttr = new Map<Id, String>{
    storageAttrId => 'SSD Hard Drive 512GB',
    processorAttrId => 'i7-CPU 4.7GHz',
    screenSizeAttrId => '15 Inch'
};

Set<String> existingRamRuleNames = new Set<String>{
    'TechNovaProBoo-RAM16',
    'TechNovaProBoo-RAM32',
    'TechNovaProBoo-RAM64'
};

Map<String, AttributeBasedAdjRule> ruleByName = new Map<String, AttributeBasedAdjRule>();
for (AttributeBasedAdjRule rule : [
    SELECT Id, Name
    FROM AttributeBasedAdjRule
    WHERE Name IN :existingRamRuleNames
       OR Name = 'TechNovaProBoo-SelectedAttrs'
]) {
    ruleByName.put(rule.Name, rule);
}

if (!ruleByName.containsKey('TechNovaProBoo-SelectedAttrs')) {
    insert new AttributeBasedAdjRule(Name = 'TechNovaProBoo-SelectedAttrs');
    ruleByName.put('TechNovaProBoo-SelectedAttrs', [
        SELECT Id, Name
        FROM AttributeBasedAdjRule
        WHERE Name = 'TechNovaProBoo-SelectedAttrs'
        LIMIT 1
    ]);
}

Set<Id> ruleIds = new Set<Id>();
for (AttributeBasedAdjRule rule : ruleByName.values()) {
    ruleIds.add(rule.Id);
}

Set<String> existingConditionKeys = new Set<String>();
for (AttributeAdjustmentCondition condition : [
    SELECT AttributeBasedAdjRuleId, AttributeDefinitionId, StringValue
    FROM AttributeAdjustmentCondition
    WHERE AttributeBasedAdjRuleId IN :ruleIds
      AND ProductId = :techNovaId
]) {
    existingConditionKeys.add(
        String.valueOf(condition.AttributeBasedAdjRuleId) + '|' +
        String.valueOf(condition.AttributeDefinitionId) + '|' +
        condition.StringValue
    );
}

List<AttributeAdjustmentCondition> conditionsToInsert = new List<AttributeAdjustmentCondition>();
for (String ramRuleName : existingRamRuleNames) {
    AttributeBasedAdjRule rule = ruleByName.get(ramRuleName);
    for (Id attrId : selectedValuesByAttr.keySet()) {
        String selectedValue = selectedValuesByAttr.get(attrId);
        String key = String.valueOf(rule.Id) + '|' + String.valueOf(attrId) + '|' + selectedValue;
        if (!existingConditionKeys.contains(key)) {
            conditionsToInsert.add(new AttributeAdjustmentCondition(
                AttributeBasedAdjRuleId = rule.Id,
                AttributeDefinitionId = attrId,
                ProductId = techNovaId,
                Operator = 'equals',
                StringValue = selectedValue
            ));
        }
    }
}

AttributeBasedAdjRule selectedRule = ruleByName.get('TechNovaProBoo-SelectedAttrs');
Map<Id, String> selectedRuleValues = new Map<Id, String>(selectedValuesByAttr);
selectedRuleValues.put(memoryAttrId, 'RAM 16GB');
for (Id attrId : selectedRuleValues.keySet()) {
    String selectedValue = selectedRuleValues.get(attrId);
    String key = String.valueOf(selectedRule.Id) + '|' + String.valueOf(attrId) + '|' + selectedValue;
    if (!existingConditionKeys.contains(key)) {
        conditionsToInsert.add(new AttributeAdjustmentCondition(
            AttributeBasedAdjRuleId = selectedRule.Id,
            AttributeDefinitionId = attrId,
            ProductId = techNovaId,
            Operator = 'equals',
            StringValue = selectedValue
        ));
    }
}

if (!conditionsToInsert.isEmpty()) {
    insert conditionsToInsert;
}

List<AttributeBasedAdjustment> existingSelectedAdjustments = [
    SELECT Id, AdjustmentValue, AdjustmentType, PriceAdjustmentScheduleId
    FROM AttributeBasedAdjustment
    WHERE ProductId = :techNovaId
      AND AttributeBasedAdjRuleId = :selectedRule.Id
];

if (existingSelectedAdjustments.isEmpty()) {
    insert new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = scheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 400,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = selectedRule.Id,
        ProductId = techNovaId
    );
} else {
    AttributeBasedAdjustment existing = existingSelectedAdjustments[0];
    Boolean changed = false;
    if (existing.PriceAdjustmentScheduleId != scheduleId) {
        existing.PriceAdjustmentScheduleId = scheduleId;
        changed = true;
    }
    if (existing.AdjustmentType != 'Amount') {
        existing.AdjustmentType = 'Amount';
        changed = true;
    }
    if (existing.AdjustmentValue != 400) {
        existing.AdjustmentValue = 400;
        changed = true;
    }
    if (changed) {
        update existing;
    }
}

update new PriceAdjustmentSchedule(Id = scheduleId, IsActive = false);
update new PriceAdjustmentSchedule(Id = scheduleId, IsActive = true);

System.debug('Inserted conditions: ' + conditionsToInsert.size());
System.debug('Ensured selected TechNova adjustment: +400');
