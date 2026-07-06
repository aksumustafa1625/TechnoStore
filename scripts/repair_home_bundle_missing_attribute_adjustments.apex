Id bundleId = '01taj00000Qp7IFAAZ';
Id scheduleId = '84Xaj000000I0SzEAK';
Id oneTimeModelId = '0jPaj000000EWphEAG';
Datetime effectiveFrom = Datetime.newInstanceGmt(2026, 1, 1, 20, 0, 0);

Id storageAttrId = '0tjaj000000FbXNAA0';
Id processorAttrId = '0tjaj000000FbXMAA0';
Id screenSizeAttrId = '0tjaj000000FbXHAA0';

List<ProductAttributeDefinition> bundlePadsToUpdate = new List<ProductAttributeDefinition>();
for (ProductAttributeDefinition pad : [
    SELECT Id, AttributeDefinitionId, IsPriceImpacting, Status
    FROM ProductAttributeDefinition
    WHERE Product2Id = :bundleId
      AND AttributeDefinitionId IN :new Set<Id>{storageAttrId, processorAttrId, screenSizeAttrId}
]) {
    Boolean changed = false;
    if (pad.Status != 'Active') {
        pad.Status = 'Active';
        changed = true;
    }
    if (pad.IsPriceImpacting != true) {
        pad.IsPriceImpacting = true;
        changed = true;
    }
    if (changed) {
        bundlePadsToUpdate.add(pad);
    }
}
if (!bundlePadsToUpdate.isEmpty()) {
    update bundlePadsToUpdate;
}

Map<String, Id> attrDefByRule = new Map<String, Id>{
    'HomeOfficeBundle-Storage512GB' => storageAttrId,
    'HomeOfficeBundle-Storage1TB' => storageAttrId,
    'HomeOfficeBundle-Storage2TB' => storageAttrId,
    'HomeOfficeBundle-StorageCloud2TB' => storageAttrId,
    'HomeOfficeBundle-StorageCloud6TB' => storageAttrId,
    'HomeOfficeBundle-Processori7' => processorAttrId,
    'HomeOfficeBundle-Processori9' => processorAttrId,
    'HomeOfficeBundle-Screen15' => screenSizeAttrId,
    'HomeOfficeBundle-Screen24' => screenSizeAttrId,
    'HomeOfficeBundle-Screen27' => screenSizeAttrId
};

Map<String, String> valueByRule = new Map<String, String>{
    'HomeOfficeBundle-Storage512GB' => 'SSD Hard Drive 512GB',
    'HomeOfficeBundle-Storage1TB' => 'SSD Hard Drive 1TB',
    'HomeOfficeBundle-Storage2TB' => 'SSD Hard Drive 2TB',
    'HomeOfficeBundle-StorageCloud2TB' => 'Cloud Storage Enterprise - 2 TB',
    'HomeOfficeBundle-StorageCloud6TB' => 'Cloud Storage Enterprise - 6 TB',
    'HomeOfficeBundle-Processori7' => 'i7-CPU 4.7GHz',
    'HomeOfficeBundle-Processori9' => 'Intel Core i9 5.2 GHz',
    'HomeOfficeBundle-Screen15' => '15 Inch',
    'HomeOfficeBundle-Screen24' => '24 Inch',
    'HomeOfficeBundle-Screen27' => '27 Inch'
};

Map<String, Decimal> amountByRule = new Map<String, Decimal>{
    'HomeOfficeBundle-Storage512GB' => 100,
    'HomeOfficeBundle-Storage1TB' => 200,
    'HomeOfficeBundle-Storage2TB' => 400,
    'HomeOfficeBundle-StorageCloud2TB' => 300,
    'HomeOfficeBundle-StorageCloud6TB' => 600,
    'HomeOfficeBundle-Processori7' => 200,
    'HomeOfficeBundle-Processori9' => 500,
    'HomeOfficeBundle-Screen15' => 100,
    'HomeOfficeBundle-Screen24' => 200,
    'HomeOfficeBundle-Screen27' => 300
};

Set<String> desiredNames = attrDefByRule.keySet();
Map<String, AttributeBasedAdjRule> ruleByName = new Map<String, AttributeBasedAdjRule>();
for (AttributeBasedAdjRule rule : [
    SELECT Id, Name
    FROM AttributeBasedAdjRule
    WHERE Name IN :desiredNames
]) {
    ruleByName.put(rule.Name, rule);
}

List<AttributeBasedAdjRule> rulesToInsert = new List<AttributeBasedAdjRule>();
for (String ruleName : desiredNames) {
    if (!ruleByName.containsKey(ruleName)) {
        rulesToInsert.add(new AttributeBasedAdjRule(Name = ruleName));
    }
}
if (!rulesToInsert.isEmpty()) {
    insert rulesToInsert;
}
for (AttributeBasedAdjRule rule : [
    SELECT Id, Name
    FROM AttributeBasedAdjRule
    WHERE Name IN :desiredNames
]) {
    ruleByName.put(rule.Name, rule);
}

Set<Id> desiredRuleIds = new Set<Id>();
for (AttributeBasedAdjRule rule : ruleByName.values()) {
    desiredRuleIds.add(rule.Id);
}

Set<Id> conditionRuleIds = new Set<Id>();
for (AttributeAdjustmentCondition condition : [
    SELECT Id, AttributeBasedAdjRuleId
    FROM AttributeAdjustmentCondition
    WHERE AttributeBasedAdjRuleId IN :desiredRuleIds
      AND ProductId = :bundleId
]) {
    conditionRuleIds.add(condition.AttributeBasedAdjRuleId);
}

List<AttributeAdjustmentCondition> conditionsToInsert = new List<AttributeAdjustmentCondition>();
for (String ruleName : desiredNames) {
    AttributeBasedAdjRule rule = ruleByName.get(ruleName);
    if (!conditionRuleIds.contains(rule.Id)) {
        conditionsToInsert.add(new AttributeAdjustmentCondition(
            AttributeBasedAdjRuleId = rule.Id,
            AttributeDefinitionId = attrDefByRule.get(ruleName),
            ProductId = bundleId,
            Operator = 'equals',
            StringValue = valueByRule.get(ruleName)
        ));
    }
}
if (!conditionsToInsert.isEmpty()) {
    insert conditionsToInsert;
}

Map<Id, AttributeBasedAdjustment> adjustmentByRuleId = new Map<Id, AttributeBasedAdjustment>();
for (AttributeBasedAdjustment adjustment : [
    SELECT Id, AttributeBasedAdjRuleId, AdjustmentValue, AdjustmentType,
           ProductSellingModelId, PriceAdjustmentScheduleId
    FROM AttributeBasedAdjustment
    WHERE AttributeBasedAdjRuleId IN :desiredRuleIds
      AND ProductId = :bundleId
]) {
    adjustmentByRuleId.put(adjustment.AttributeBasedAdjRuleId, adjustment);
}

List<AttributeBasedAdjustment> adjustmentsToInsert = new List<AttributeBasedAdjustment>();
List<AttributeBasedAdjustment> adjustmentsToUpdate = new List<AttributeBasedAdjustment>();
for (String ruleName : desiredNames) {
    AttributeBasedAdjRule rule = ruleByName.get(ruleName);
    Decimal amount = amountByRule.get(ruleName);
    AttributeBasedAdjustment existing = adjustmentByRuleId.get(rule.Id);

    if (existing == null) {
        adjustmentsToInsert.add(new AttributeBasedAdjustment(
            PriceAdjustmentScheduleId = scheduleId,
            AdjustmentType = 'Amount',
            AdjustmentValue = amount,
            EffectiveFrom = effectiveFrom,
            AttributeBasedAdjRuleId = rule.Id,
            ProductId = bundleId,
            ProductSellingModelId = oneTimeModelId
        ));
    } else {
        Boolean changed = false;
        if (existing.PriceAdjustmentScheduleId != scheduleId) {
            existing.PriceAdjustmentScheduleId = scheduleId;
            changed = true;
        }
        if (existing.AdjustmentType != 'Amount') {
            existing.AdjustmentType = 'Amount';
            changed = true;
        }
        if (existing.AdjustmentValue != amount) {
            existing.AdjustmentValue = amount;
            changed = true;
        }
        if (existing.ProductSellingModelId != oneTimeModelId) {
            existing.ProductSellingModelId = oneTimeModelId;
            changed = true;
        }
        if (changed) {
            adjustmentsToUpdate.add(existing);
        }
    }
}

if (!adjustmentsToInsert.isEmpty()) {
    insert adjustmentsToInsert;
}
if (!adjustmentsToUpdate.isEmpty()) {
    update adjustmentsToUpdate;
}

update new PriceAdjustmentSchedule(Id = scheduleId, IsActive = false);
update new PriceAdjustmentSchedule(Id = scheduleId, IsActive = true);

System.debug('Inserted rules: ' + rulesToInsert.size());
System.debug('Updated bundle product attributes: ' + bundlePadsToUpdate.size());
System.debug('Inserted conditions: ' + conditionsToInsert.size());
System.debug('Inserted adjustments: ' + adjustmentsToInsert.size());
System.debug('Updated adjustments: ' + adjustmentsToUpdate.size());
