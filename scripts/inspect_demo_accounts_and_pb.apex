// Inspect accounts + pricebook + a representative existing product

System.debug('======== Demo accounts ========');
for (Account a : [SELECT Id, Name, Industry, NumberOfEmployees, BillingCountry FROM Account ORDER BY CreatedDate DESC LIMIT 30]) {
    System.debug('  ' + a.Name + ' | Industry=' + a.Industry + ' | Employees=' + a.NumberOfEmployees + ' | Country=' + a.BillingCountry);
}

System.debug('======== Standard Pricebook ========');
Pricebook2 standard = [SELECT Id, Name, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
System.debug('  Standard PB: ' + standard);
List<Pricebook2> custom = [SELECT Id, Name, IsActive FROM Pricebook2 WHERE IsStandard = false AND IsActive = true LIMIT 5];
for (Pricebook2 pb : custom) System.debug('  Custom active PB: ' + pb);

System.debug('======== Existing Enterprise Bundle product ========');
Product2 enterprise = [SELECT Id, Name, ProductCode, Family, Description, ConfigureDuringSale, BasedOnId, IsActive, Type
                       FROM Product2 WHERE Id = '01taj00000QmKgdAAF'];
System.debug(enterprise);

System.debug('======== PricebookEntries for Enterprise Bundle ========');
for (PricebookEntry pbe : [SELECT Id, Pricebook2.Name, UnitPrice, IsActive FROM PricebookEntry WHERE Product2Id = '01taj00000QmKgdAAF']) {
    System.debug('  ' + pbe.Pricebook2.Name + ' | Price=' + pbe.UnitPrice + ' | Active=' + pbe.IsActive);
}

System.debug('======== ProductQualification for Enterprise Bundle ========');
for (ProductQualification pq : [SELECT Id, IsQualified, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate
                                FROM ProductQualification WHERE ProductId = '01taj00000QmKgdAAF']) {
    System.debug(pq);
}

System.debug('======== ProductDisqualification for Enterprise Bundle ========');
for (ProductDisqualification pdq : [SELECT Id, Industry__c, Reason, EffectiveFromDate, EffectiveToDate
                                    FROM ProductDisqualification WHERE ProductId = '01taj00000QmKgdAAF']) {
    System.debug('  ' + pdq.Industry__c + ' | Reason=' + pdq.Reason);
}
