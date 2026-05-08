// Look at the existing PQ records to understand the pattern in use

System.debug('======== ProductQualification records (FULL) ========');
for (ProductQualification pq : [
    SELECT Id, Name, ProductId, Product.Name, IsQualified, EffectiveFromDate, EffectiveToDate,
           MinNumberOfEmployees__c, MaxNumberOfEmployees__c, ParentProductId, RootProductId
    FROM ProductQualification ORDER BY CreatedDate DESC LIMIT 30
]) {
    System.debug(pq);
}

System.debug('======== ProductDisqualification records ========');
for (ProductDisqualification pdq : [
    SELECT Id, Name, ProductId, Product.Name, IsDisqualified, EffectiveFromDate, EffectiveToDate,
           Industry__c, Reason
    FROM ProductDisqualification ORDER BY CreatedDate DESC LIMIT 30
]) {
    System.debug(pdq);
}

System.debug('======== Industry__c picklist values on ProductDisqualification ========');
Schema.DescribeFieldResult d = Schema.SObjectType.ProductDisqualification.fields.getMap().get('industry__c').getDescribe();
for (Schema.PicklistEntry pe : d.getPicklistValues()) {
    System.debug('  ' + pe.getValue() + ' (label=' + pe.getLabel() + ')');
}

System.debug('======== Account.Industry picklist values ========');
Schema.DescribeFieldResult ai = Schema.SObjectType.Account.fields.getMap().get('industry').getDescribe();
for (Schema.PicklistEntry pe : ai.getPicklistValues()) {
    System.debug('  ' + pe.getValue());
}
