// Delete ProductAttributeDefinition overrides on Home Office Bundle
// so we can change BasedOn classification
Id bundleId = '01taj00000Qp7IFAAZ';

List<ProductAttributeDefinition> overrides = [
    SELECT Id, Name FROM ProductAttributeDefinition WHERE Product2Id = :bundleId
];

System.debug('Found ' + overrides.size() + ' overrides to delete');
delete overrides;
System.debug('Deleted ' + overrides.size() + ' ProductAttributeDefinition overrides');
