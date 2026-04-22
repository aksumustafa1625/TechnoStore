// Enable debug tracing for current user
// Deletes old trace flags and creates a fresh one with full Apex logging

// Get current user
User u = [SELECT Id, Username FROM User WHERE Username = 'technostore-admin@example.com' LIMIT 1];
System.debug('User: ' + u.Id);

// Delete existing trace flags for this user
List<TraceFlag> oldFlags = [SELECT Id FROM TraceFlag WHERE TracedEntityId = :u.Id];
if (!oldFlags.isEmpty()) {
    delete oldFlags;
    System.debug('Deleted ' + oldFlags.size() + ' old trace flags');
}

// Get or create a debug level
DebugLevel dl;
List<DebugLevel> existing = [SELECT Id FROM DebugLevel WHERE DeveloperName = 'SFDC_DevConsole' LIMIT 1];
if (!existing.isEmpty()) {
    dl = existing[0];
} else {
    dl = new DebugLevel();
    dl.DeveloperName = 'BrowseDebug';
    dl.MasterLabel = 'Browse Debug';
    dl.ApexCode = 'DEBUG';
    dl.ApexProfiling = 'INFO';
    dl.Callout = 'INFO';
    dl.Database = 'INFO';
    dl.System = 'DEBUG';
    dl.Validation = 'INFO';
    dl.Visualforce = 'INFO';
    dl.Workflow = 'INFO';
    insert dl;
}

// Create new trace flag - expires in 2 hours
TraceFlag tf = new TraceFlag();
tf.TracedEntityId = u.Id;
tf.DebugLevelId = dl.Id;
tf.LogType = 'USER_DEBUG';
tf.StartDate = DateTime.now();
tf.ExpirationDate = DateTime.now().addHours(2);
insert tf;

System.debug('SUCCESS: Created TraceFlag: ' + tf.Id + ', expires: ' + tf.ExpirationDate);
