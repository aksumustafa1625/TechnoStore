Id oneTimeModelId = '0jPaj000000EWphEAG';
Id bundleId = '01taj00000Qp7IFAAZ';
Id sharedScheduleId = '84Xaj000000I0SzEAK';
Datetime effectiveFrom = Datetime.newInstanceGmt(2026, 1, 1, 20, 0, 0);

// Step A: Get the existing rules so we can reuse their IDs
Map<String, Id> ruleIdByName = new Map<String, Id>();
for (AttributeBasedAdjRule r : [SELECT Id, Name FROM AttributeBasedAdjRule WHERE Name LIKE 'HomeOfficeBundle-RAM%']) {
    ruleIdByName.put(r.Name, r.Id);
}
System.debug('Rules: ' + ruleIdByName);

// Step B: Delete old adjustments (they have null ProductSellingModelId)
List<AttributeBasedAdjustment> oldAdj = [SELECT Id FROM AttributeBasedAdjustment WHERE ProductId=:bundleId];
delete oldAdj;
System.debug('Deleted ' + oldAdj.size() + ' old adjustments');

// Step C: Re-create with ProductSellingModelId = One Time
List<AttributeBasedAdjustment> newAdj = new List<AttributeBasedAdjustment>{
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 100,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = ruleIdByName.get('HomeOfficeBundle-RAM16'),
        ProductId = bundleId,
        ProductSellingModelId = oneTimeModelId
    ),
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 200,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = ruleIdByName.get('HomeOfficeBundle-RAM32'),
        ProductId = bundleId,
        ProductSellingModelId = oneTimeModelId
    ),
    new AttributeBasedAdjustment(
        PriceAdjustmentScheduleId = sharedScheduleId,
        AdjustmentType = 'Amount',
        AdjustmentValue = 400,
        EffectiveFrom = effectiveFrom,
        AttributeBasedAdjRuleId = ruleIdByName.get('HomeOfficeBundle-RAM64'),
        ProductId = bundleId,
        ProductSellingModelId = oneTimeModelId
    )
};
insert newAdj;
System.debug('Inserted ' + newAdj.size() + ' new adjustments with One Time selling model');

// Step D: Cycle the schedule (deactivate → reactivate)
update new PriceAdjustmentSchedule(Id=sharedScheduleId, IsActive=false);
update new PriceAdjustmentSchedule(Id=sharedScheduleId, IsActive=true);
System.debug('Schedule cycled');

// Verify
for (AttributeBasedAdjustment a : [SELECT AdjustmentValue, ProductSellingModel.SellingModelType FROM AttributeBasedAdjustment WHERE ProductId=:bundleId ORDER BY AdjustmentValue]) {
    System.debug('Final: +$' + a.AdjustmentValue + ' SellingModel=' + a.ProductSellingModel.SellingModelType);
}
