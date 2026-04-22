// Test Contract creation directly without CLM
// This will help us understand if the issue is with CLM or Contract object itself

System.debug('=== Testing Direct Contract Creation ===');

// Get the Order
Order ord = [SELECT Id, OrderNumber, Name, AccountId, Account.Name, 
             Status, EffectiveDate, EndDate, Pricebook2Id
             FROM Order 
             WHERE Id = '801aj00002XST9VAAX' LIMIT 1];

System.debug('Order Info:');
System.debug('- Order Number: ' + ord.OrderNumber);
System.debug('- Order Name: ' + ord.Name);
System.debug('- Account: ' + ord.Account.Name);
System.debug('- Status: ' + ord.Status);
System.debug('- EffectiveDate: ' + ord.EffectiveDate);

// Try to create a Contract manually (without CLM API)
try {
    Contract c = new Contract();
    c.AccountId = ord.AccountId;
    c.Status = 'Draft';
    c.StartDate = ord.EffectiveDate != null ? ord.EffectiveDate : Date.today();
    c.ContractTerm = 12; // 12 months
    c.Description = ord.Name; // Put Order name in Description
    
    System.debug('\n=== Attempting Manual Contract Creation ===');
    System.debug('Contract AccountId: ' + c.AccountId);
    System.debug('Contract StartDate: ' + c.StartDate);
    System.debug('Contract Description: ' + c.Description);
    
    insert c;
    
    System.debug('\n✓ SUCCESS! Manual Contract Created!');
    System.debug('Contract ID: ' + c.Id);
    System.debug('Contract Number: ' + [SELECT ContractNumber FROM Contract WHERE Id = :c.Id].ContractNumber);
    
    // Now link it to the Order
    ord.ContractId = c.Id;
    update ord;
    
    System.debug('✓ Order linked to Contract!');
    System.debug('\nConclusion: Contract creation works fine.');
    System.debug('The issue is specifically with the CLM API or field mapping configuration.');
    
} catch(Exception e) {
    System.debug('\n✗ FAILED to create Contract manually!');
    System.debug('Error: ' + e.getMessage());
    System.debug('Stack Trace: ' + e.getStackTraceString());
    System.debug('\nThis means there is a deeper issue with Contract creation permissions or validation rules.');
}

// Check all Contract fields to see what's actually available
System.debug('\n=== All Writable Contract Fields ===');
Schema.DescribeSObjectResult contractDescribe = Contract.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fields = contractDescribe.fields.getMap();

List<String> writableFields = new List<String>();
for(String fieldName : fields.keySet()) {
    Schema.DescribeFieldResult fdr = fields.get(fieldName).getDescribe();
    if(fdr.isCreateable() && fdr.getType() == Schema.DisplayType.STRING) {
        writableFields.add(fieldName + ' (' + fdr.getLabel() + ')');
    }
}

System.debug('Writable Text fields on Contract:');
for(String field : writableFields) {
    System.debug('  - ' + field);
}