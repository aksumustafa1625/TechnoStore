// Clone TechNova ProBook 15's RAM-based price adjustments to Home Office Bundle
// So that selecting RAM 32GB (or 64GB) in bundle Configure increases the price

Id sourceProductId = '01taj00000QnnlNAAR'; // TechNova ProBook 15
Id targetProductId = '01taj00000Qp7IFAAZ'; // Home Office Bundle
Id ramAttributeId = '0tjaj000000FbXJAA0';   // Memory attribute definition
Id sharedScheduleId = '84Xaj000000I0SzEAK'; // Existing PriceAdjustmentSchedule
Datetime effectiveFrom = Datetime.newInstanceGmt(2026, 1, 1, 20, 0, 0);

// Step 1: Create 3 new AttributeBasedAdjRule records for the bundle
List<AttributeBasedAdjRule> newRules = new List<AttributeBasedAdjRule>{
    new AttributeBasedAdjRule(Name='HomeOfficeBundle-RAM16'),
    new AttributeBasedAdjRule(Name='HomeOfficeBundle-RAM32'),
    new AttributeBasedAdjRule(Name='HomeOfficeBundle-RAM64')
};
insert newRules;
System.debug('Inserted ' + newRules.size() + ' new rules');

// Step 2: Create 3 AttributeAdjustmentCondition (one per rule, mapping to RAM picklist value)
List<AttributeAdjustmentCondition> newConditions = new List<AttributeAdjustmentCondition>{
    new AttributeAdjustmentCondition(
        AttributeBasedAdjRuleId = newRules[0].Id,
        AttributeDefinitionId = ramAttributeId,
        ProductId = targetProductId,
        Operator = 'equals',
        StringValue = 'RAM 16GB'
    ),
    new AttributeAdjustmentCondition(
        AttributeBasedAdjRuleId = newRules[1].Id,
        AttributeDefinitionId = ramAttributeId,
        ProductId = targetProductId,
        Operator = 'equals',
        StringValue = 'RAM 32GB'
    ),
    new AttributeAdjustmentCondition(
        AttributeBasedAdjRuleId = newRules[2].Id,
        AttributeDefinitionId = ramAttributeId,
        ProductId = targetProductId,
        Operator = 'equals',
        StringValue = 'RAM 64GB'
    )
};
insert newConditions;
System.debug('Inserted ' + newConditions.size() + ' new conditions');

// Step 3: Create 3 AttributeBasedAdjustment records ($100, $200, $400)
List<AttributeBasedAdjustment> newAdjustments = new List<AttributeBasedAdjustment>{
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 100,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = newRules[0].Id,
        ProductId = targetProductId
    ),
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 200,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = newRules[1].Id,
        ProductId = targetProductId
    ),
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 400,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = newRules[2].Id,
        ProductId = targetProductId
    )
};
insert newAdjustments;
System.debug('Inserted ' + newAdjustments.size() + ' new adjustments');

// Verify
for (AttributeBasedAdjustment a : [SELECT Id, AdjustmentValue, AttributeBasedAdjRule.Name FROM AttributeBasedAdjustment WHERE ProductId=:targetProductId]) {
    System.debug('Bundle adj: ' + a.AttributeBasedAdjRule.Name + ' = +$' + a.AdjustmentValue);
}
