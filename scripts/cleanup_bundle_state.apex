// Cleanup: revert MinBundle/MaxBundle to null + delete duplicate Home Office Bundle QLIs from Köln
update new ProductComponentGroup(Id='0y7aj000000CdC6AAK', MinBundleComponents=null, MaxBundleComponents=null);
System.debug('Reverted Group min/max to null');

// Delete duplicate bundle QLIs on Köln quote
List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem WHERE QuoteId='0Q0aj000002IHalCAG'];
System.debug('Deleting ' + qlis.size() + ' QLIs on Köln quote');
delete qlis;

// Verify Köln quote is empty
List<QuoteLineItem> after = [SELECT Id FROM QuoteLineItem WHERE QuoteId='0Q0aj000002IHalCAG'];
System.debug('Köln QLIs after delete: ' + after.size());
