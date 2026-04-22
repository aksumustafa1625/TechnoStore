// Deep investigation of CLM Contract creation issue
// This script will help us understand what's really happening

System.debug('=== Investigating CLM Contract Creation Issue ===');

// Get the Order that's causing the problem
Order ord = [SELECT Id, OrderNumber, Name, AccountId, Account.Name, Status, 
             BillingStreet, BillingCity, BillingState, BillingPostalCode,
             EffectiveDate, EndDate, ContractId
             FROM Order 
             WHERE Id = '801aj00002XST9VAAX' LIMIT 1];

System.debug('Order Details:');
System.debug('- Order Number: ' + ord.OrderNumber);
System.debug('- Order Name: ' + ord.Name);
System.debug('- Account: ' + ord.Account.Name);
System.debug('- Status: ' + ord.Status);
System.debug('- EffectiveDate: ' + ord.EffectiveDate);
System.debug('- EndDate: ' + ord.EndDate);

// Check if Order has required fields for Contract creation
System.debug('\n=== Checking Required Fields ===');
System.debug('Order.Name is populated: ' + (ord.Name != null && ord.Name != ''));
System.debug('Order.AccountId is populated: ' + (ord.AccountId != null));
System.debug('Order.Status: ' + ord.Status);
System.debug('Order.EffectiveDate: ' + ord.EffectiveDate);

// Try to understand what ConnectApi.Clm.createContract needs
System.debug('\n=== Contract Object Analysis ===');
Schema.DescribeSObjectResult contractDescribe = Contract.SObjectType.getDescribe();
Map<String, Schema.SObjectField> contractFields = contractDescribe.fields.getMap();

List<String> requiredFields = new List<String>();
for(String fieldName : contractFields.keySet()) {
    Schema.DescribeFieldResult fieldDescribe = contractFields.get(fieldName).getDescribe();
    if(!fieldDescribe.isNillable() && fieldDescribe.isCreateable() && !fieldDescribe.isDefaultedOnCreate()) {
        requiredFields.add(fieldName + ' (' + fieldDescribe.getLabel() + ')');
    }
}

System.debug('Required Contract fields on create:');
for(String field : requiredFields) {
    System.debug('  - ' + field);
}

// Check if there's an existing field mapping metadata
System.debug('\n=== Checking for Custom Metadata ===');
List<SObject> mappings = Database.query('SELECT QualifiedApiName, DeveloperName, MasterLabel FROM EntityDefinition WHERE QualifiedApiName LIKE \'%Mapping%\' OR QualifiedApiName LIKE \'%FieldMap%\' LIMIT 10');
System.debug('Found potential mapping metadata types: ' + mappings.size());
for(SObject mapping : mappings) {
    System.debug('  - ' + mapping.get('QualifiedApiName'));
}

System.debug('\n=== SOLUTION ===');
System.debug('The issue is likely:');
System.debug('1. CLM is trying to map to a "Name" field on Contract');
System.debug('2. But Contract does NOT have a standard Name field');
System.debug('3. We need to either:');
System.debug('   a) Check Setup > CLM > Field Mappings and remove/update the Name mapping');
System.debug('   b) Ensure the mapping uses Name__c instead of Name');
System.debug('   c) Or provide the value through a different approach');