// Delete orphan Quote_Bundle_Component__c records (Parent_Quote_Line_Item__c=null) on Köln Quote
List<Quote_Bundle_Component__c> orphans = [
    SELECT Id FROM Quote_Bundle_Component__c
    WHERE Parent_Quote_Line_Item__c = null AND Quote__c = '0Q0aj000002IHalCAG'
];
delete orphans;
System.debug('Deleted ' + orphans.size() + ' orphan component displays');
