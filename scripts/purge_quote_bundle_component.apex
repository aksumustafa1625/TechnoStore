// Delete all Quote_Bundle_Component__c records before destructive metadata deploy can remove the object
Integer before = Database.countQuery('SELECT COUNT() FROM Quote_Bundle_Component__c');
System.debug('Records before: ' + before);

List<SObject> rows = Database.query('SELECT Id FROM Quote_Bundle_Component__c LIMIT 1000');
if (!rows.isEmpty()) {
    Database.DeleteResult[] dr = Database.delete(rows, false);
    Integer ok = 0;
    Integer fail = 0;
    for (Database.DeleteResult r : dr) { if (r.isSuccess()) ok++; else fail++; }
    System.debug('Deleted: ' + ok + ' Failed: ' + fail);
}

Integer after = Database.countQuery('SELECT COUNT() FROM Quote_Bundle_Component__c');
System.debug('Records after: ' + after);
