// Minimal test - what fields does AttributeDefinition need?
AttributePicklist testPl = [SELECT Id FROM AttributePicklist WHERE Code = 'External_Monitor_Resolution' LIMIT 1];

AttributeDefinition def = new AttributeDefinition();
def.Name = 'Resolution';
def.Code = 'External_Monitor_Resolution';
def.DeveloperName = 'External_Monitor_Resolution';
def.Label = 'Resolution';
def.DataType = 'Picklist';
def.PicklistId = testPl.Id;
def.IsActive = true;
def.IsRequired = false;

try {
    insert def;
    System.debug('SUCCESS: Inserted ' + def.Id);
    delete def;
    System.debug('Cleaned up');
} catch (Exception e) {
    System.debug('FAILED: ' + e.getMessage());
    System.debug('Type: ' + e.getTypeName());
}
