// Diagnose Contract Name Field Mapping Issue
// This script helps identify the field mapping configuration problem

System.debug('=== Contract Field Mapping Diagnosis ===');

// Check if Contract has a Name field
Schema.DescribeSObjectResult contractDescribe = Contract.SObjectType.getDescribe();
Map<String, Schema.SObjectField> contractFields = contractDescribe.fields.getMap();

System.debug('Contract Object Label: ' + contractDescribe.getLabel());
System.debug('Contract has Name field: ' + contractFields.containsKey('Name'));
System.debug('Contract has ContractNumber field: ' + contractFields.containsKey('ContractNumber'));

if (contractFields.containsKey('Name')) {
    Schema.DescribeFieldResult nameField = contractFields.get('Name').getDescribe();
    System.debug('Name field details: ' + nameField);
} else {
    System.debug('Contract does NOT have a Name field - this is the root cause!');
}

// Check Order fields
Schema.DescribeSObjectResult orderDescribe = Order.SObjectType.getDescribe();
Map<String, Schema.SObjectField> orderFields = orderDescribe.fields.getMap();

System.debug('\nOrder Object Label: ' + orderDescribe.getLabel());
System.debug('Order has Name field: ' + orderFields.containsKey('Name'));
System.debug('Order has OrderNumber field: ' + orderFields.containsKey('OrderNumber'));

if (orderFields.containsKey('Name')) {
    Schema.DescribeFieldResult nameField = orderFields.get('Name').getDescribe();
    System.debug('Order.Name field is: ' + nameField.getLabel() + ' (Type: ' + nameField.getType() + ')');
}

System.debug('\n=== Solution ===');
System.debug('The Contract object does not have a Name field.');
System.debug('Contract uses ContractNumber (auto-generated) instead.');
System.debug('You need to either:');
System.debug('1. Create a custom Name field on Contract object, OR');
System.debug('2. Remove/fix the Order.Name -> Contract.Name mapping in CLM setup');
System.debug('3. Navigate to: Setup > Contract Lifecycle Management > Field Mappings');