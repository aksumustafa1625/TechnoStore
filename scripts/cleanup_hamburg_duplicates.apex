// Delete the $1,599 phantom Bundle and its duplicate 3 children on Hamburg DataWorks quote
List<Id> toDelete = new List<Id>{
    '0QLaj000002Yl8DGAS', // phantom Home Office Bundle ($1,599)
    '0QLaj000002Yl9sGAC', // duplicate Wireless Combo Set
    '0QLaj000002Yl9tGAC', // duplicate ErgoMouse Vertical
    '0QLaj000002Yl9uGAC'  // duplicate WebCam Pro 4K Studio
};
List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem WHERE Id IN :toDelete];
delete qlis;
System.debug('Deleted ' + qlis.size() + ' duplicate QLIs');
