// Discover ProductCategoryDisqualification + ProductCategoryQualification field set

// Try via dynamic describe
Schema.DescribeSObjectResult pcdDescribe = Schema.getGlobalDescribe().get('ProductCategoryDisqualification').getDescribe();
System.debug('======== ProductCategoryDisqualification fields ========');
for (String f : new List<String>(pcdDescribe.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = pcdDescribe.fields.getMap().get(f).getDescribe();
    if (d.isAccessible() && d.getType() != Schema.DisplayType.ADDRESS) {
        System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo() + ' | Updateable=' + d.isUpdateable());
    }
}

Schema.DescribeSObjectResult pcqDescribe = Schema.getGlobalDescribe().get('ProductCategoryQualification').getDescribe();
System.debug('======== ProductCategoryQualification fields ========');
for (String f : new List<String>(pcqDescribe.fields.getMap().keySet())) {
    Schema.DescribeFieldResult d = pcqDescribe.fields.getMap().get(f).getDescribe();
    if (d.isAccessible() && d.getType() != Schema.DisplayType.ADDRESS) {
        System.debug('  ' + f + ' | ' + d.getType() + ' | Updateable=' + d.isUpdateable());
    }
}

// Skip — relying on describe output above
