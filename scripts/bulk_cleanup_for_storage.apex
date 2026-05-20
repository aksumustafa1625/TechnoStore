// === STORAGE CLEANUP — preserve only the SAP test evidence ===
// Target: free Data Storage below 60% (currently 97%, 4.85MB/5MB)
// User explicitly approved (2026-05-18 ~22:00). Catalog (Product2 + PricebookEntry) PRESERVED.

// Disable triggers that might side-effect during bulk delete
try { TriggerHandler.bypass('OrderTriggerHandler'); } catch (Exception e) {}
try { TriggerHandler.bypass('OrderItemTriggerHandler'); } catch (Exception e) {}
try { TriggerHandler.bypass('QuoteLineItemTriggerHandler'); } catch (Exception e) {}
try { TriggerHandler.bypass('DocumentRecipientTriggerHandler'); } catch (Exception e) {}

// =========================================================
// KEEP LIST — collect ids that survive
// =========================================================
Set<Id> keepAccountIds = new Set<Id>();
for (Account a : [SELECT Id FROM Account WHERE SAP_BP_Number__c != null]) keepAccountIds.add(a.Id);
System.debug('Keeping Accounts (SAP-synced): ' + keepAccountIds.size());

Set<Id> keepOrderIds = new Set<Id>();
for (Order o : [SELECT Id FROM Order WHERE OrderNumber = '00000170']) keepOrderIds.add(o.Id);

Set<Id> keepInvoiceIds = new Set<Id>();
for (Invoice inv : [SELECT Id FROM Invoice WHERE DocumentNumber IN ('DOC-000000016','DOC-000000017')]) keepInvoiceIds.add(inv.Id);

System.debug('Keep totals — Account:' + keepAccountIds.size() + ' Order:' + keepOrderIds.size() + ' Invoice:' + keepInvoiceIds.size());

// Tracker for recycle bin emptying
List<sObject> allDeleted = new List<sObject>();

Integer totalDeleted = 0;
Integer totalFailed = 0;

// =========================================================
// DELETE in dependency order
// =========================================================

// --- 1. Assets (all — they're cascading orphans from old deleted orders) ---
List<Asset> assets = [SELECT Id FROM Asset];
if (!assets.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(assets, false);
    Integer ok=0, fail=0;
    for (Database.DeleteResult dr : r) { if (dr.isSuccess()) { ok++; allDeleted.add(new Asset(Id=assets[r.indexOf(dr)].Id)); } else fail++; }
    System.debug('Asset deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
}

// --- 2. OrderItems not linked to keepOrderIds ---
List<OrderItem> orderItems = [SELECT Id FROM OrderItem WHERE OrderId NOT IN :keepOrderIds];
if (!orderItems.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(orderItems, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('OrderItem deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (OrderItem oi : orderItems) allDeleted.add(new OrderItem(Id=oi.Id));
}

// --- 3. Orders not in keep list ---
List<Order> orders = [SELECT Id, Status FROM Order WHERE Id NOT IN :keepOrderIds];
// Deactivate first if Activated (Order.Status='Activated' records may need to go to Draft before delete)
List<Order> toDeactivate = new List<Order>();
for (Order o : orders) if (o.Status == 'Activated') toDeactivate.add(new Order(Id=o.Id, Status='Draft'));
if (!toDeactivate.isEmpty()) {
    Database.SaveResult[] sr = Database.update(toDeactivate, false);
    Integer okU=0; for (Database.SaveResult res : sr) if (res.isSuccess()) okU++;
    System.debug('Orders deactivated for delete: ' + okU + '/' + toDeactivate.size());
}
if (!orders.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(orders, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Order deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Order o : orders) allDeleted.add(new Order(Id=o.Id));
}

// --- 4. Demo_Invoice__c (legacy) ---
try {
    List<SObject> di = Database.query('SELECT Id FROM Demo_Invoice__c');
    if (!di.isEmpty()) {
        Database.DeleteResult[] r = Database.delete(di, false);
        Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
        System.debug('Demo_Invoice__c deleted: ' + ok + ' / failed: ' + fail);
        totalDeleted += ok; totalFailed += fail;
        allDeleted.addAll(di);
    }
} catch (Exception e) { System.debug('Demo_Invoice__c skip: ' + e.getMessage()); }

// --- 5. Invoice (not in keep list) ---
List<Invoice> invs = [SELECT Id FROM Invoice WHERE Id NOT IN :keepInvoiceIds];
if (!invs.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(invs, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Invoice deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Invoice i : invs) allDeleted.add(new Invoice(Id=i.Id));
}

// --- 6. QuoteLineItem then Quote ---
List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem];
if (!qlis.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(qlis, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('QuoteLineItem deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (QuoteLineItem q : qlis) allDeleted.add(new QuoteLineItem(Id=q.Id));
}
List<Quote> quotes = [SELECT Id FROM Quote];
if (!quotes.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(quotes, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Quote deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Quote q : quotes) allDeleted.add(new Quote(Id=q.Id));
}

// --- 7. Opportunity ---
List<Opportunity> opps = [SELECT Id FROM Opportunity];
if (!opps.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(opps, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Opportunity deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Opportunity o : opps) allDeleted.add(new Opportunity(Id=o.Id));
}

// --- 8. Contact (not linked to kept Accounts) ---
List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId NOT IN :keepAccountIds];
if (!contacts.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(contacts, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Contact deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Contact c : contacts) allDeleted.add(new Contact(Id=c.Id));
}

// --- 9. Lead ---
List<Lead> leads = [SELECT Id FROM Lead];
if (!leads.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(leads, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Lead deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Lead l : leads) allDeleted.add(new Lead(Id=l.Id));
}

// --- 10. Account (not in keep list) ---
List<Account> accts = [SELECT Id FROM Account WHERE Id NOT IN :keepAccountIds];
if (!accts.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(accts, false);
    Integer ok=0, fail=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++; else fail++;
    System.debug('Account deleted: ' + ok + ' / failed: ' + fail);
    totalDeleted += ok; totalFailed += fail;
    for (Account a : accts) allDeleted.add(new Account(Id=a.Id));
}

// --- 11. EmailMessage, FeedItem, Task ---
List<EmailMessage> emails = [SELECT Id FROM EmailMessage];
if (!emails.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(emails, false);
    Integer ok=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++;
    System.debug('EmailMessage deleted: ' + ok);
    totalDeleted += ok;
    for (EmailMessage em : emails) allDeleted.add(new EmailMessage(Id=em.Id));
}
List<FeedItem> feeds = [SELECT Id FROM FeedItem];
if (!feeds.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(feeds, false);
    Integer ok=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++;
    System.debug('FeedItem deleted: ' + ok);
    totalDeleted += ok;
    for (FeedItem f : feeds) allDeleted.add(new FeedItem(Id=f.Id));
}
List<Task> tasks = [SELECT Id FROM Task];
if (!tasks.isEmpty()) {
    Database.DeleteResult[] r = Database.delete(tasks, false);
    Integer ok=0; for (Database.DeleteResult dr : r) if (dr.isSuccess()) ok++;
    System.debug('Task deleted: ' + ok);
    totalDeleted += ok;
    for (Task t : tasks) allDeleted.add(new Task(Id=t.Id));
}

// --- 12. Service_Activation__c, Webhook_Event__c, Integration_Error__c ---
try {
    List<SObject> sa = Database.query('SELECT Id FROM Service_Activation__c');
    if (!sa.isEmpty()) { Database.delete(sa, false); System.debug('Service_Activation__c: ' + sa.size()); totalDeleted += sa.size(); allDeleted.addAll(sa); }
} catch (Exception e) {}
try {
    List<SObject> we = Database.query('SELECT Id FROM Webhook_Event__c');
    if (!we.isEmpty()) { Database.delete(we, false); System.debug('Webhook_Event__c: ' + we.size()); totalDeleted += we.size(); allDeleted.addAll(we); }
} catch (Exception e) {}
try {
    List<SObject> ie = Database.query('SELECT Id FROM Integration_Error__c');
    if (!ie.isEmpty()) { Database.delete(ie, false); System.debug('Integration_Error__c: ' + ie.size()); totalDeleted += ie.size(); allDeleted.addAll(ie); }
} catch (Exception e) {}

System.debug('---');
System.debug('TOTAL DELETED: ' + totalDeleted + '  FAILED: ' + totalFailed);
System.debug('Tracking ' + allDeleted.size() + ' records for Recycle Bin purge');

// =========================================================
// EMPTY RECYCLE BIN — CRITICAL for actual storage reclamation
// =========================================================
// Batches of 200 (Database.emptyRecycleBin limit)
Integer emptied = 0;
Integer emptyFailed = 0;
Integer batchSize = 200;
for (Integer i = 0; i < allDeleted.size(); i += batchSize) {
    Integer endIdx = Math.min(i + batchSize, allDeleted.size());
    List<sObject> batch = new List<sObject>();
    for (Integer j = i; j < endIdx; j++) batch.add(allDeleted[j]);
    try {
        Database.EmptyRecycleBinResult[] er = Database.emptyRecycleBin(batch);
        for (Database.EmptyRecycleBinResult res : er) { if (res.isSuccess()) emptied++; else emptyFailed++; }
    } catch (Exception e) {
        System.debug('emptyRecycleBin batch fail: ' + e.getMessage());
        emptyFailed += batch.size();
    }
}
System.debug('RECYCLE BIN EMPTIED: ' + emptied + ' / FAILED: ' + emptyFailed);
System.debug('Now refresh Setup → Storage Usage in browser to verify storage drop.');
