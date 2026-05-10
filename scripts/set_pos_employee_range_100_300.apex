// Engine doesn't enforce Industry-based ProductDisqualification in this org —
// only NumberOfEmployees range works. Move POS qualification to Min=100, Max=300
// (mid-market retail size range).
//
// Demo accounts at default values:
//   Köln Retail Cloud (Retail, 180 emp)        -> in range, sees POS
//   Hamburg DataWorks AG (Tech, 320 emp)       -> above, hidden
//   München Industrial (Manufacturing, 580)    -> above, hidden
//   Frankfurt FinTech Hub (Finance, 410 emp)   -> above, hidden
//
// Industry blocks (31 records per product) kept as Setup-visible documentation
// even though the engine doesn't enforce them — they reinforce the narrative
// "POS targeted at retail" without changing runtime behavior.

Set<String> posCodes = new Set<String>{'POS01','ENPOS101','REG01','SCN01'};

List<ProductQualification> pqs = [SELECT Id, MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE Product.ProductCode IN :posCodes];
for (ProductQualification pq : pqs) {
    pq.MinNumberOfEmployees__c = 100;
    pq.MaxNumberOfEmployees__c = 300;
    pq.EffectiveFromDate = Date.today().addDays(-1);
    pq.EffectiveToDate = Date.newInstance(2099, 12, 31);
}
update pqs;
System.debug('Updated ' + pqs.size() + ' POS ProductQualification records to Min=100, Max=300');

System.debug('======== Verification ========');
for (ProductQualification pq : [SELECT Product.Name, MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE Product.ProductCode IN :posCodes ORDER BY Product.Name]) {
    System.debug('  ' + pq.Product.Name + ' | Min=' + pq.MinNumberOfEmployees__c + ' | Max=' + pq.MaxNumberOfEmployees__c);
}
