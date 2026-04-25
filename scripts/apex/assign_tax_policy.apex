List<Product2> prods = [SELECT Id, Name FROM Product2 WHERE IsActive = true AND TaxPolicyId = null];
System.debug('Products without TaxPolicyId: ' + prods.size());
for (Product2 p : prods) {
    p.TaxPolicyId = '1Tpaj000000IKTJCA4';
}
Database.SaveResult[] results = Database.update(prods, false);
Integer ok = 0, fail = 0;
for (Database.SaveResult r : results) {
    if (r.isSuccess()) ok++;
    else {
        fail++;
        System.debug('FAIL ' + r.getId() + ': ' + r.getErrors());
    }
}
System.debug('Updated OK: ' + ok + ', Failed: ' + fail);
