// Clean up TEST rules and any partial adjustments. DO NOT delete RAM rules — those are working.
List<AttributeBasedAdjRule> testRules = [SELECT Id FROM AttributeBasedAdjRule WHERE Name LIKE 'HomeOfficeBundle-TEST%' OR Name LIKE 'HomeOfficeBundle-Storage%' OR Name LIKE 'HomeOfficeBundle-Processor%' OR Name LIKE 'HomeOfficeBundle-Screen%'];
System.debug('Test rules to delete: ' + testRules.size());

// Delete adjustments first (they reference the rule)
List<AttributeBasedAdjustment> testAdjustments = [SELECT Id FROM AttributeBasedAdjustment WHERE AttributeBasedAdjRuleId IN :testRules];
delete testAdjustments;
System.debug('Deleted ' + testAdjustments.size() + ' test adjustments');

delete testRules;
System.debug('Deleted ' + testRules.size() + ' test rules');
