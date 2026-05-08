// Try to programmatically trigger the Salesforce Pricing Setup Sync
// (runs after qualification rule changes; rebuilds the runtime lookup tables).

System.debug('Attempting to trigger pricing setup sync via ConnectApi...');
try {
    // Check available Connect API namespaces
    Type t = Type.forName('ConnectApi.RevenueLifecycleManagement');
    if (t == null) {
        t = Type.forName('connectapi.RevenueLifecycleManagement');
    }
    System.debug('Type: ' + t);
} catch (Exception e) {
    System.debug('Connect API check failed: ' + e.getMessage());
}

// Fall back: try invoking PricingSetupSync via REST/Tooling API
// In practice, this is run from Setup -> Salesforce Pricing -> Sync.
System.debug('If qualification changes are not reflected in Browse Catalog, manually run:');
System.debug('  Setup -> Salesforce Pricing -> Run Sync');
System.debug('OR');
System.debug('  Setup -> Salesforce Pricing Setup -> Run Initial Sync / Run Incremental Sync');
