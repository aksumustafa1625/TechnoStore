// Step 1: Set ProductSellingModelId on the 3 Bundle adjustments
Id oneTimeModelId = '0jPaj000000EWphEAG';
Id bundleId = '01taj00000Qp7IFAAZ';

List<AttributeBasedAdjustment> adjustments = [
    SELECT Id, AdjustmentValue, ProductSellingModelId
    FROM AttributeBasedAdjustment WHERE ProductId = :bundleId
];
for (AttributeBasedAdjustment a : adjustments) a.ProductSellingModelId = oneTimeModelId;
update adjustments;

System.debug('Updated ' + adjustments.size() + ' adjustments with One Time ProductSellingModelId');
for (AttributeBasedAdjustment a : [SELECT AdjustmentValue, ProductSellingModelId, ProductSellingModel.SellingModelType FROM AttributeBasedAdjustment WHERE ProductId=:bundleId]) {
    System.debug('Adjustment +$' + a.AdjustmentValue + ' SellingModel=' + a.ProductSellingModel.SellingModelType);
}

// Step 2: Force refresh the Memory Upgrade Pricing schedule (deactivate → save → reactivate)
update new PriceAdjustmentSchedule(Id='84Xaj000000I0SzEAK', IsActive=false);
System.debug('Schedule deactivated');
update new PriceAdjustmentSchedule(Id='84Xaj000000I0SzEAK', IsActive=true);
System.debug('Schedule reactivated');

PriceAdjustmentSchedule s = [SELECT Id, Name, IsActive FROM PriceAdjustmentSchedule WHERE Id='84Xaj000000I0SzEAK'];
System.debug('Schedule final state: ' + s.Name + ' Active=' + s.IsActive);
