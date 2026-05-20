// ============================================================
// PHASE 7 DEMO — SAP Event Mesh Inbound (CloudEvents)
// Shows: SAP pushes a "BusinessPartner Changed" event -> webhook dispatcher
//        -> Salesforce Account audit field auto-updates.
// Recording-friendly: prints BEFORE state, dispatches the event, prints AFTER state.
// ============================================================

// 1. Pick a synced Account (has SAP_BP_Number__c) and show its current state
Account acct = [
    SELECT Id, Name, SAP_BP_Number__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c
    FROM Account WHERE SAP_BP_Number__c != null ORDER BY SAP_Last_Synced_At__c DESC LIMIT 1
];
System.debug('========== BEFORE ==========');
System.debug('Account: ' + acct.Name + ' (SAP BP ' + acct.SAP_BP_Number__c + ')');
System.debug('  SAP_Customer_Group__c : ' + acct.SAP_Customer_Group__c);
System.debug('  SAP_Last_Synced_At__c : ' + acct.SAP_Last_Synced_At__c);

// 2. Toggle the target group so the change is visible on every run (BP01 <-> BP02)
String newGroup = (acct.SAP_Customer_Group__c == 'BP02') ? 'BP01' : 'BP02';

// 3. Build the CloudEvent 1.0 envelope exactly as SAP Event Mesh would publish it
SapInboundEventDispatcher.CloudEvent ce = new SapInboundEventDispatcher.CloudEvent();
ce.eventId   = 'demo-bp-' + System.currentTimeMillis();
ce.eventType = 'sap.s4.beh.businesspartner.v1.BusinessPartner.Changed.v1';
ce.subject   = acct.SAP_BP_Number__c;
ce.source    = '/sap/s4hanacloud';
ce.data      = new Map<String, Object>{
    'BusinessPartner'         => acct.SAP_BP_Number__c,
    'BusinessPartnerGrouping' => newGroup
};

System.debug('========== SAP EVENT MESH -> WEBHOOK ==========');
System.debug('CloudEvent type   : ' + ce.eventType);
System.debug('CloudEvent subject: BP ' + ce.subject);
System.debug('New grouping      : ' + newGroup);

// 4. Dispatch (same code path the /sap/event REST webhook invokes after HMAC + idempotency checks)
SapInboundEventDispatcher.dispatch(ce);

// 5. Re-read the Account and show the auto-updated state
Account after = [
    SELECT Id, Name, SAP_Customer_Group__c, SAP_Last_Synced_At__c
    FROM Account WHERE Id = :acct.Id
];
System.debug('========== AFTER ==========');
System.debug('  SAP_Customer_Group__c : ' + after.SAP_Customer_Group__c + '   <-- auto-updated by inbound event');
System.debug('  SAP_Last_Synced_At__c : ' + after.SAP_Last_Synced_At__c);

if (after.SAP_Customer_Group__c == newGroup) {
    System.debug('>>> PHASE 7 SUCCESS: inbound SAP event updated the Salesforce Account in real time.');
}
