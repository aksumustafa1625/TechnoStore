// Probe: insert 1 small PDQ record to test if storage is actually free.

Id testProductId = [SELECT Id FROM Product2 WHERE ProductCode = 'POS01' LIMIT 1].Id;
ProductDisqualification probe = new ProductDisqualification(
    ProductId = testProductId,
    Industry__c = 'Healthcare',
    Reason = 'Storage probe ' + DateTime.now().getTime(),
    EffectiveFromDate = Date.today().addDays(-1),
    EffectiveToDate = Date.newInstance(2099, 12, 31)
);

try {
    insert probe;
    System.debug('SUCCESS — storage is free. Test record inserted: ' + probe.Id);

    // Roll it back so we don't pollute
    delete probe;
    Database.emptyRecycleBin(new List<Id>{probe.Id});
    System.debug('Test record cleaned up.');
} catch (Exception e) {
    System.debug('FAIL — storage still full: ' + e.getMessage());
}

// Also count actual records consuming storage
Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification];
Integer pqCount = [SELECT COUNT() FROM ProductQualification];
Integer pcpCount = [SELECT COUNT() FROM ProductCategoryProduct];
Integer pbeCount = [SELECT COUNT() FROM PricebookEntry];
Integer prodCount = [SELECT COUNT() FROM Product2];
Integer cdsCount = [SELECT COUNT() FROM ContextDefinitionSync];
System.debug('Record counts:');
System.debug('  ProductDisqualification:    ' + pdqCount);
System.debug('  ProductQualification:       ' + pqCount);
System.debug('  ProductCategoryProduct:     ' + pcpCount);
System.debug('  PricebookEntry:             ' + pbeCount);
System.debug('  Product2:                   ' + prodCount);
System.debug('  ContextDefinitionSync:      ' + cdsCount);
