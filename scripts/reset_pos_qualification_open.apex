// Reset POS qualification back to open (Min=0, Max=999999) so all employee counts qualify.
// Industry filtering is now handled by the Block_POS_Products_For_Non_Retail_Accounts flow
// at QuoteLineItem save time.

Set<String> posCodes = new Set<String>{'POS01','ENPOS101','REG01','SCN01'};
List<ProductQualification> pqs = [SELECT Id FROM ProductQualification WHERE Product.ProductCode IN :posCodes];
for (ProductQualification pq : pqs) {
    pq.MinNumberOfEmployees__c = 0;
    pq.MaxNumberOfEmployees__c = 999999;
}
update pqs;
System.debug('Reset ' + pqs.size() + ' POS PQs to Min=0 Max=999999');

for (ProductQualification pq : [SELECT Product.Name, MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE Product.ProductCode IN :posCodes ORDER BY Product.Name]) {
    System.debug('  ' + pq.Product.Name + ' | Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c);
}
