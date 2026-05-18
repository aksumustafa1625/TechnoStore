// Use dynamic SOQL to avoid Apex compile-time access checks
for (String objName : new List<String>{'Techno_Attribute_Price_Rule__c', 'Quote_Bundle_Component__c'}) {
    try {
        Integer cnt = Database.countQuery('SELECT COUNT() FROM ' + objName);
        System.debug(objName + ' records: ' + cnt);
    } catch (Exception e) {
        System.debug(objName + ' query failed: ' + e.getMessage());
    }
}
