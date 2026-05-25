// Isolate the Lead insert from the WhatsApp webhook to find the real error.
try {
    Lead l = new Lead(
        LastName    = 'WhatsApp Lead +491601234567',
        Company     = 'WhatsApp Inbound',
        Phone       = '+491601234567',
        Description = 'test message',
        Status      = 'Open - Not Contacted'
    );
    insert l;
    System.debug('SUCCESS — Lead created: ' + l.Id);
    delete l; // cleanup
} catch (Exception e) {
    System.debug('LEAD INSERT FAILED: ' + e.getMessage());
}

// Show valid Lead Status picklist values in THIS org
System.debug('=== Valid Lead Status values ===');
for (Schema.PicklistEntry pe : Lead.Status.getDescribe().getPicklistValues()) {
    System.debug('  ' + pe.getValue() + (pe.isDefaultValue() ? '  (DEFAULT)' : ''));
}
