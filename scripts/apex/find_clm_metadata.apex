// Find CLM metadata and configuration
// This will help us locate the exact mapping causing the issue

System.debug('=== Searching for CLM Metadata ===');

// Try to find any CLM-related custom metadata
try {
    List<SObject> contexts = Database.query('SELECT Id, DeveloperName, MasterLabel FROM ContextDefinition');
    System.debug('\n=== Context Definitions Found: ' + contexts.size() + ' ===');
    for(SObject ctx : contexts) {
        System.debug('  - ' + ctx.get('DeveloperName') + ' (' + ctx.get('MasterLabel') + ')');
    }
} catch(Exception e) {
    System.debug('ContextDefinition not queryable: ' + e.getMessage());
}

// Try to find field mappings through different objects
try {
    List<SObject> mappings = Database.query('SELECT Id, DeveloperName, MasterLabel FROM ContextMapping__mdt LIMIT 10');
    System.debug('\n=== Custom Metadata Mappings Found: ' + mappings.size() + ' ===');
    for(SObject m : mappings) {
        System.debug('  - ' + m.get('DeveloperName'));
    }
} catch(Exception e) {
    System.debug('ContextMapping__mdt not found: ' + e.getMessage());
}

// Check for ContextAttributeMapping
try {
    String query = 'SELECT Id, ContextDefinitionKey, ContextNodeFieldName, ' +
                   'ContextNodeKey, DataType FROM ContextAttributeMapping LIMIT 20';
    List<SObject> attrMappings = Database.query(query);
    System.debug('\n=== Context Attribute Mappings Found: ' + attrMappings.size() + ' ===');
    for(SObject am : attrMappings) {
        System.debug('  - Context: ' + am.get('ContextDefinitionKey') + 
                     ', Node: ' + am.get('ContextNodeKey') + 
                     ', Field: ' + am.get('ContextNodeFieldName'));
    }
} catch(Exception e) {
    System.debug('ContextAttributeMapping not queryable: ' + e.getMessage());
}

// Check for ContextNodeMapping - this might have the Name field mapping!
try {
    String query = 'SELECT Id, ContextDefinitionKey, ContextNodeKey, ' +
                   'ObjectType, FieldMappingOrder FROM ContextNodeMapping LIMIT 20';
    List<SObject> nodeMappings = Database.query(query);
    System.debug('\n=== Context Node Mappings Found: ' + nodeMappings.size() + ' ===');
    for(SObject nm : nodeMappings) {
        if(String.valueOf(nm.get('ObjectType')).contains('Contract') || 
           String.valueOf(nm.get('ObjectType')).contains('Order')) {
            System.debug('  - Object: ' + nm.get('ObjectType') + 
                         ', Context: ' + nm.get('ContextDefinitionKey') +
                         ', Node: ' + nm.get('ContextNodeKey'));
        }
    }
} catch(Exception e) {
    System.debug('ContextNodeMapping not queryable: ' + e.getMessage());
}

System.debug('\n=== Recommendation ===');
System.debug('If no CLM metadata found, the field mapping might be in:');
System.debug('1. Setup > Process Automation > Flows (check for Order-related flows)');
System.debug('2. Setup > Object Manager > Order > Buttons, Links, and Actions');
System.debug('3. Or directly in the ConnectApi.Clm configuration');
System.debug('\nThe error suggests CLM is trying to map Order.Name to Contract.Name');
System.debug('This might be a default CLM behavior that needs to be overridden');