// Check CLM Setup and Field Mappings using Tooling API
// This will help us find the exact configuration issue

System.debug('=== Checking CLM Configuration ===');

// Try to query using Tooling API objects
try {
    // Check if there's a field mapping setup
    String query = 'SELECT Id, DeveloperName, MasterLabel, NamespacePrefix FROM FieldMapping';
    List<SObject> fieldMappings = Database.query(query);
    System.debug('Found FieldMapping records: ' + fieldMappings.size());
    for(SObject fm : fieldMappings) {
        System.debug('  - ' + fm.get('DeveloperName'));
    }
} catch(Exception e) {
    System.debug('FieldMapping object not found or not accessible: ' + e.getMessage());
}

// Check for Order-related metadata
try {
    Schema.DescribeSObjectResult orderDescribe = Order.SObjectType.getDescribe();
    System.debug('\n=== Order Object Info ===');
    System.debug('Order fields we need:');
    System.debug('  - Name: ' + orderDescribe.fields.getMap().containsKey('Name'));
    System.debug('  - AccountId: ' + orderDescribe.fields.getMap().containsKey('AccountId'));
    System.debug('  - EffectiveDate: ' + orderDescribe.fields.getMap().containsKey('EffectiveDate'));
    System.debug('  - ContractId: ' + orderDescribe.fields.getMap().containsKey('ContractId'));
} catch(Exception e) {
    System.debug('Error: ' + e.getMessage());
}

// Now let's check the actual Contract fields available
System.debug('\n=== Contract Fields Available ===');
Schema.DescribeSObjectResult contractDescribe = Contract.SObjectType.getDescribe();
Map<String, Schema.SObjectField> contractFieldsMap = contractDescribe.fields.getMap();

List<String> relevantFields = new List<String>();
for(String fieldName : contractFieldsMap.keySet()) {
    if(fieldName.toLowerCase().contains('name') || 
       fieldName.toLowerCase().contains('title') ||
       fieldName.toLowerCase().contains('description')) {
        Schema.DescribeFieldResult fdr = contractFieldsMap.get(fieldName).getDescribe();
        relevantFields.add(fieldName + ' (' + fdr.getLabel() + ') - Type: ' + fdr.getType());
    }
}

System.debug('Name-related fields on Contract:');
for(String field : relevantFields) {
    System.debug('  - ' + field);
}

System.debug('\n=== KEY FINDING ===');
System.debug('Contract.Name__c exists: ' + contractFieldsMap.containsKey('name__c'));
if(contractFieldsMap.containsKey('name__c')) {
    System.debug('✓ Name__c field is deployed and ready to use!');
    System.debug('The CLM field mapping must be updated in Setup to use Name__c');
} else {
    System.debug('✗ Name__c field not found - deployment may have failed');
}