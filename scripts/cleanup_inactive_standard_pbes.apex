// Hard-delete the leftover inactive Standard PricebookEntry duplicates

List<PricebookEntry> stale = [
    SELECT Id, Product2.Name, Pricebook2.Name, UnitPrice, IsActive
    FROM PricebookEntry
    WHERE Product2.ProductCode IN ('COMP-WS-OFFICE','COMP-WS-BUSINESS','COMP-WS-HYPERSCALE','COMP-WS-PREMIUM','COMP-WS-STUDIO')
      AND Pricebook2.IsStandard = true
      AND IsActive = false
];
System.debug('Found ' + stale.size() + ' inactive Standard PBE duplicates to delete');
for (PricebookEntry pbe : stale) {
    System.debug('  ' + pbe.Product2.Name + ' | ' + pbe.Pricebook2.Name + ' | $' + pbe.UnitPrice);
}

List<Database.DeleteResult> drs = Database.delete(stale, false);
Integer ok = 0, fail = 0;
for (Integer i = 0; i < drs.size(); i++) {
    if (drs[i].isSuccess()) ok++;
    else {
        fail++;
        System.debug('FAIL ' + stale[i].Id + ' (' + stale[i].Product2.Name + '): ' + drs[i].getErrors()[0].getMessage());
    }
}
System.debug('Deleted: ' + ok + ' | Failed: ' + fail);

// Verify final state
System.debug('======== FINAL ========');
for (AggregateResult ar : [
    SELECT Product2.Name name, COUNT(Id) cnt
    FROM PricebookEntry
    WHERE Product2.ProductCode IN ('COMP-WS-OFFICE','COMP-WS-BUSINESS','COMP-WS-HYPERSCALE','COMP-WS-PREMIUM','COMP-WS-STUDIO','COMP-WS-001','COMP-WS-002')
    GROUP BY Product2.Name
    ORDER BY Product2.Name
]) {
    System.debug('  ' + ar.get('name') + ' | ' + ar.get('cnt') + ' PBEs');
}
