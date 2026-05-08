// Try to trigger a Pricing Setup Sync programmatically.
// Multiple approaches because Salesforce hasn't standardized this.

// Approach 1: Call ConnectApi for IndustriesCpqAdmin / SalesforcePricing
try {
    Type t = Type.forName('ConnectApi.SalesforcePricing');
    System.debug('ConnectApi.SalesforcePricing: ' + t);
} catch (Exception e) {
    System.debug('ConnectApi.SalesforcePricing not available: ' + e.getMessage());
}

try {
    Type t = Type.forName('ConnectApi.RevenueLifecycleManagement');
    System.debug('ConnectApi.RevenueLifecycleManagement: ' + t);
} catch (Exception e) {
    System.debug('ConnectApi.RevenueLifecycleManagement not available: ' + e.getMessage());
}

// Approach 2: Insert a ContextDefinitionSync record manually (request fresh sync)
try {
    ContextDefinitionSync sync = new ContextDefinitionSync();
    insert sync;
    System.debug('ContextDefinitionSync triggered: ' + sync.Id);
} catch (Exception e) {
    System.debug('ContextDefinitionSync insert failed: ' + e.getMessage());
}

// Approach 3: Investigate fields to see what's required
System.debug('======== ContextDefinitionSync writable fields ========');
for (String f : new List<String>(Schema.SObjectType.ContextDefinitionSync.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = Schema.SObjectType.ContextDefinitionSync.fields.getMap().get(f).getDescribe();
    if (d.isCreateable()) {
        System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo() + ' | Required=' + !d.isNillable());
    }
}

System.debug('======== Existing ContextDefinitionSync state ========');
for (ContextDefinitionSync cds : [SELECT Id FROM ContextDefinitionSync ORDER BY CreatedDate DESC LIMIT 3]) {
    System.debug('  ' + cds);
}
