// Add attribute-based adjustments for Storage, Processor, Screen Size on Home Office Bundle.
// Mirrors the existing RAM pattern: AttributeBasedAdjRule + AttributeAdjustmentCondition +
// AttributeBasedAdjustment, all attached to the shared HomeOfficeBundle PriceAdjustmentSchedule.
// Also updates AttributePicklistValue Name+DisplayValue with " (+$X)" so the dropdown shows
// the price differential to the user. Cycles the schedule at the end to activate the new rules.

Id bundleId        = '01taj00000Qp7IFAAZ';
Id scheduleId      = '84Xaj000000I0SzEAK';
Id oneTimeModelId  = '0jPaj000000EWphEAG';
Datetime effectiveFrom = Datetime.newInstanceGmt(2026, 1, 1, 20, 0, 0);

Id storageAttrId   = '0tjaj000000FbXNAA0';
Id processorAttrId = '0tjaj000000FbXMAA0';
Id screenSizeAttrId = '0tjaj000000FbXHAA0';

// ---------- Step 1: Create AttributeBasedAdjRule records ----------
// rule key -> (rule object). Skip if a rule with same Name already exists.
Map<String, AttributeBasedAdjRule> rulesToInsert = new Map<String, AttributeBasedAdjRule>{
    'HomeOfficeBundle-Storage512GB' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Storage512GB'),
    'HomeOfficeBundle-Storage1TB' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Storage1TB'),
    'HomeOfficeBundle-Storage2TB' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Storage2TB'),
    'HomeOfficeBundle-StorageCloud2TB' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-StorageCloud2TB'),
    'HomeOfficeBundle-StorageCloud6TB' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-StorageCloud6TB'),
    'HomeOfficeBundle-Processori7' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Processori7'),
    'HomeOfficeBundle-Processori9' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Processori9'),
    'HomeOfficeBundle-Screen15' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Screen15'),
    'HomeOfficeBundle-Screen24' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Screen24'),
    'HomeOfficeBundle-Screen27' => new AttributeBasedAdjRule(Name='HomeOfficeBundle-Screen27')
};
Set<String> existingNames = new Set<String>();
for (AttributeBasedAdjRule r : [SELECT Name FROM AttributeBasedAdjRule WHERE Name IN :rulesToInsert.keySet()]) {
    existingNames.add(r.Name);
}
List<AttributeBasedAdjRule> newRules = new List<AttributeBasedAdjRule>();
for (String n : rulesToInsert.keySet()) {
    if (!existingNames.contains(n)) newRules.add(rulesToInsert.get(n));
}
if (!newRules.isEmpty()) insert newRules;
System.debug('Created ' + newRules.size() + ' new rules (existing: ' + existingNames.size() + ')');

// Re-query to get IDs (existing + new)
Map<String, Id> ruleIdByName = new Map<String, Id>();
for (AttributeBasedAdjRule r : [SELECT Id, Name FROM AttributeBasedAdjRule WHERE Name IN :rulesToInsert.keySet()]) {
    ruleIdByName.put(r.Name, r.Id);
}

// ---------- Step 2: Create AttributeAdjustmentCondition records ----------
// rule name -> {attributeDefId, value-string-stored-on-AttributePicklistValue.Value}
List<AttributeAdjustmentCondition> conditionsToInsert = new List<AttributeAdjustmentCondition>{
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Storage512GB'),    AttributeDefinitionId=storageAttrId,    Operator='equals', StringValue='SSD Hard Drive 512GB'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Storage1TB'),       AttributeDefinitionId=storageAttrId,    Operator='equals', StringValue='SSD Hard Drive 1TB'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Storage2TB'),       AttributeDefinitionId=storageAttrId,    Operator='equals', StringValue='SSD Hard Drive 2TB'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-StorageCloud2TB'),  AttributeDefinitionId=storageAttrId,    Operator='equals', StringValue='Cloud Storage Enterprise - 2 TB'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-StorageCloud6TB'),  AttributeDefinitionId=storageAttrId,    Operator='equals', StringValue='Cloud Storage Enterprise - 6 TB'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Processori7'),      AttributeDefinitionId=processorAttrId,  Operator='equals', StringValue='i7-CPU 4.7GHz'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Processori9'),      AttributeDefinitionId=processorAttrId,  Operator='equals', StringValue='Intel Core i9 5.2 GHz'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Screen15'),         AttributeDefinitionId=screenSizeAttrId, Operator='equals', StringValue='15 Inch'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Screen24'),         AttributeDefinitionId=screenSizeAttrId, Operator='equals', StringValue='24 Inch'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=ruleIdByName.get('HomeOfficeBundle-Screen27'),         AttributeDefinitionId=screenSizeAttrId, Operator='equals', StringValue='27 Inch')
};
// Skip conditions that already exist for the same rule
Set<Id> rulesWithConditions = new Set<Id>();
for (AttributeAdjustmentCondition c : [SELECT AttributeBasedAdjRuleId FROM AttributeAdjustmentCondition WHERE AttributeBasedAdjRuleId IN :ruleIdByName.values()]) {
    rulesWithConditions.add(c.AttributeBasedAdjRuleId);
}
List<AttributeAdjustmentCondition> newConditions = new List<AttributeAdjustmentCondition>();
for (AttributeAdjustmentCondition c : conditionsToInsert) {
    if (!rulesWithConditions.contains(c.AttributeBasedAdjRuleId)) newConditions.add(c);
}
if (!newConditions.isEmpty()) insert newConditions;
System.debug('Created ' + newConditions.size() + ' new conditions');

// ---------- Step 3: Create AttributeBasedAdjustment records ----------
Map<String, Decimal> adjustmentByRule = new Map<String, Decimal>{
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
Set<Id> rulesWithAdjustments = new Set<Id>();
for (AttributeBasedAdjustment a : [SELECT AttributeBasedAdjRuleId FROM AttributeBasedAdjustment WHERE AttributeBasedAdjRuleId IN :ruleIdByName.values() AND ProductId=:bundleId]) {
    rulesWithAdjustments.add(a.AttributeBasedAdjRuleId);
}
List<AttributeBasedAdjustment> newAdjustments = new List<AttributeBasedAdjustment>();
for (String ruleName : adjustmentByRule.keySet()) {
    Id ruleId = ruleIdByName.get(ruleName);
    if (rulesWithAdjustments.contains(ruleId)) continue;
    newAdjustments.add(new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = scheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = adjustmentByRule.get(ruleName),
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = ruleId,
        ProductId = bundleId,
        ProductSellingModelId = oneTimeModelId
    ));
}
if (!newAdjustments.isEmpty()) insert newAdjustments;
System.debug('Created ' + newAdjustments.size() + ' new adjustments');

// ---------- Step 4: Update picklist labels with price differential suffix ----------
// Updates Name + DisplayValue ONLY. Value field stays at the original (used by trigger matching).
List<AttributePicklistValue> labelUpdates = new List<AttributePicklistValue>{
    // Storage
    new AttributePicklistValue(Id='0v6aj000000G24iAAC', Name='SSD Hard Drive 512GB (+$100)', DisplayValue='SSD Hard Drive 512GB (+$100)'),
    new AttributePicklistValue(Id='0v6aj000000G24gAAC', Name='SSD Hard Drive 1TB (+$200)',   DisplayValue='SSD Hard Drive 1TB (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24jAAC', Name='SSD Hard Drive 2TB (+$400)',   DisplayValue='SSD Hard Drive 2TB (+$400)'),
    new AttributePicklistValue(Id='0v6aj000000G24fAAC', Name='Cloud Storage 2TB (+$300)',    DisplayValue='Cloud Storage 2TB (+$300)'),
    new AttributePicklistValue(Id='0v6aj000000G24kAAC', Name='Cloud Storage 6TB (+$600)',    DisplayValue='Cloud Storage 6TB (+$600)'),
    // Processor
    new AttributePicklistValue(Id='0v6aj000000G24cAAC', Name='i7-CPU 4.7GHz (+$200)',        DisplayValue='i7-CPU 4.7GHz (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24dAAC', Name='Intel Core i9 5.2 GHz (+$500)',DisplayValue='Intel Core i9 5.2 GHz (+$500)'),
    // Screen Size
    new AttributePicklistValue(Id='0v6aj000000G24RAAS', Name='15 Inch (+$100)',              DisplayValue='15 Inch (+$100)'),
    new AttributePicklistValue(Id='0v6aj000000G24QAAS', Name='24 Inch (+$200)',              DisplayValue='24 Inch (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24OAAS', Name='27 Inch (+$300)',              DisplayValue='27 Inch (+$300)')
};
update labelUpdates;
System.debug('Updated ' + labelUpdates.size() + ' picklist labels');

// ---------- Step 5: Cycle the schedule to register new rules ----------
update new PriceAdjustmentSchedule(Id=scheduleId, IsActive=false);
update new PriceAdjustmentSchedule(Id=scheduleId, IsActive=true);
System.debug('Schedule cycled — new rules now active');
