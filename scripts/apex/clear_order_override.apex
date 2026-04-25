Order o = [SELECT Id, OrderNumber, TotalAmountOverride, AdjustmentDistributionLogic FROM Order WHERE Id = '801aj00002fQbT7AAK'];
System.debug('Before: Override=' + o.TotalAmountOverride + ' ADL=' + o.AdjustmentDistributionLogic);

Order u = new Order(Id=o.Id, TotalAmountOverride=null, AdjustmentDistributionLogic=null);
try { update u; System.debug('Override cleared'); }
catch (Exception e) { System.debug('Clear fail: ' + e.getMessage()); }

Order after = [SELECT Id, TotalAmountOverride, AdjustmentDistributionLogic, Tax_Amount__c, Total_With_Tax__c FROM Order WHERE Id = '801aj00002fQbT7AAK'];
System.debug('After: Override=' + after.TotalAmountOverride + ' ADL=' + after.AdjustmentDistributionLogic + ' Tax=' + after.Tax_Amount__c + ' Total=' + after.Total_With_Tax__c);
