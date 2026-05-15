// Wipe demo data. Iteration 2: handles activated Orders + diagnostics.

System.debug('===== CLEANUP START =====');

TriggerHandler.bypass('OrderItemTriggerHandler');
TriggerHandler.bypass('QuoteLineItemTriggerHandler');
TriggerHandler.bypass('DocumentRecipientTriggerHandler');
TriggerHandler.bypass('DocuSignStatusUpdateTriggerHandler');

// ============================================================
// Phase 1: Deactivate activated Orders so they can be deleted
// ============================================================
try {
    List<Order> activeOrders = [SELECT Id, Status FROM Order WHERE Status = 'Activated'];
    if (!activeOrders.isEmpty()) {
        for (Order o : activeOrders) { o.Status = 'Draft'; }
        Database.SaveResult[] sr = Database.update(activeOrders, false);
        Integer ok = 0, ko = 0;
        for (Database.SaveResult r : sr) {
            if (r.isSuccess()) ok++;
            else { ko++; System.debug('Deactivate err: ' + r.getErrors()[0].getMessage()); }
        }
        System.debug('Order deactivation: ' + ok + ' ok / ' + ko + ' failed');
    }
} catch (Exception e) {
    System.debug('Deactivate phase err: ' + e.getMessage());
}

// ============================================================
// Phase 2: Iterative delete in correct order with error logging
// ============================================================
List<String> sobjects = new List<String>{
    'AssetContractRelationship',
    'AssetRelationship',
    'Asset',
    'OrderItem',
    'Order',
    'ContractDocumentVersion',
    'Contract',
    'QuoteDocument',
    'QuoteLineItem',
    'Quote',
    'OpportunityContactRole',
    'OpportunityLineItem',
    'Opportunity',
    'Contact',
    'Account'
};

for (String sobjName : sobjects) {
    try {
        List<SObject> rows = Database.query('SELECT Id FROM ' + sobjName);
        if (rows.isEmpty()) {
            System.debug('  ' + sobjName + ': empty');
            continue;
        }
        Database.DeleteResult[] dr = Database.delete(rows, false);
        Integer ok = 0, ko = 0;
        Set<String> errors = new Set<String>();
        for (Database.DeleteResult r : dr) {
            if (r.isSuccess()) ok++;
            else {
                ko++;
                if (errors.size() < 3 && !r.getErrors().isEmpty()) {
                    errors.add(r.getErrors()[0].getMessage().left(150));
                }
            }
        }
        System.debug('  ' + sobjName + ': ' + ok + ' deleted, ' + ko + ' failed');
        for (String err : errors) System.debug('    ↳ ' + err);
    } catch (Exception e) {
        System.debug('  ' + sobjName + ': SKIPPED (' + e.getMessage().left(150) + ')');
    }
}

TriggerHandler.clearBypass('OrderItemTriggerHandler');
TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
TriggerHandler.clearBypass('DocumentRecipientTriggerHandler');
TriggerHandler.clearBypass('DocuSignStatusUpdateTriggerHandler');

// ============================================================
// Final state
// ============================================================
System.debug('===== POST-CLEANUP STATE =====');
System.debug('Accounts:       ' + [SELECT count() FROM Account]);
System.debug('Opportunities:  ' + [SELECT count() FROM Opportunity]);
System.debug('Quotes:         ' + [SELECT count() FROM Quote]);
System.debug('Orders:         ' + [SELECT count() FROM Order]);
System.debug('Contracts:      ' + [SELECT count() FROM Contract]);
System.debug('Assets:         ' + [SELECT count() FROM Asset]);
System.debug('Contacts:       ' + [SELECT count() FROM Contact]);
System.debug('===== CLEANUP DONE =====');

// Show what remains
List<Account> remaining = [SELECT Id, Name FROM Account];
if (!remaining.isEmpty()) {
    System.debug('Remaining accounts:');
    for (Account a : remaining) System.debug('  - ' + a.Name);
}
