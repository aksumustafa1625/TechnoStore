Integer totalCustomObjects = 0;
Integer totalEvents = 0;
Integer totalMdts = 0;
Integer totalCustSet = 0;

// EntityDefinition allows max 200 per query; multiple windowed queries needed.
List<EntityDefinition> pageA = [SELECT QualifiedApiName, IsCustomSetting FROM EntityDefinition WHERE QualifiedApiName < 'M' ORDER BY QualifiedApiName LIMIT 200];
List<EntityDefinition> pageB = [SELECT QualifiedApiName, IsCustomSetting FROM EntityDefinition WHERE QualifiedApiName >= 'M' ORDER BY QualifiedApiName LIMIT 200];
List<EntityDefinition> all = new List<EntityDefinition>();
all.addAll(pageA);
all.addAll(pageB);
System.debug('Pages: A=' + pageA.size() + ' B=' + pageB.size() + ' Combined=' + all.size());
for (EntityDefinition e : all) {
    String n = e.QualifiedApiName;
    if (n == null) continue;
    String typ = null;
    if (n.endsWith('__e')) { typ = 'EVENT  '; totalEvents++; }
    else if (n.endsWith('__mdt')) { typ = 'MDT    '; totalMdts++; }
    else if (n.endsWith('__c')) {
        if (e.IsCustomSetting) { typ = 'CUSTSET'; totalCustSet++; }
        else { typ = 'CUSTOBJ'; totalCustomObjects++; }
    }
    if (typ != null) System.debug(typ + ' | ' + n);
}
System.debug('Totals — CustomObj:' + totalCustomObjects + ' Events:' + totalEvents + ' MDTs:' + totalMdts + ' CustSettings:' + totalCustSet);
