// Replicate the WhatsApp webhook's internal flow to find the failing step.
try {
    System.debug('Step 1: checkAndRecord...');
    WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord('SMtest-internal-' + System.currentTimeMillis(), 'WhatsApp', 'inbound.message', 'test body');
    System.debug('  isDuplicate=' + r.isDuplicate + ' rowId=' + (r.row != null ? r.row.Id : null));

    System.debug('Step 2: insert Lead...');
    Lead l = new Lead(LastName='WA test', Company='WA Inbound', Phone='+49160', Description='hi', Status='Open - Not Contacted');
    insert l;
    System.debug('  Lead=' + l.Id);

    System.debug('Step 3: markProcessed...');
    WebhookEventLogger.markProcessed(r.row, l.Id);
    System.debug('  markProcessed OK');

    delete l;
    System.debug('ALL STEPS OK');
} catch (Exception e) {
    System.debug('FAILED AT: ' + e.getTypeName() + ' | ' + e.getMessage() + ' | line ' + e.getLineNumber());
}
