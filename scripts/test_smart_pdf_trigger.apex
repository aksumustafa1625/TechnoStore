// Test the smart trigger end-to-end on Contract 00000300 (Draft, AccountId set,
// StartDate null). This is the realistic "create with partial data" scenario.
//
// Expected:
//   1. Initially: AccountId set but StartDate/EndDate null → entry condition false → no PDF generated yet
//   2. Set StartDate + EndDate + ContractTerm → ALL fields populated AND ISCHANGED → flow fires → 1 PDF
//   3. Touch Description → entry condition false (no ISCHANGED on key fields) → no regen, same DocId
//   4. Touch StartDate → ISCHANGED → flow fires → old PDF deleted, new inserted, different DocId

Id contractId = [SELECT Id FROM Contract WHERE ContractNumber = '00000300' LIMIT 1].Id;

System.debug('======== STEP 0: Initial state ========');
Contract c0 = [SELECT Id, AccountId, StartDate, EndDate, ContractTerm FROM Contract WHERE Id = :contractId];
System.debug('  AccountId=' + c0.AccountId + ' | StartDate=' + c0.StartDate + ' | EndDate=' + c0.EndDate + ' | ContractTerm=' + c0.ContractTerm);
List<ContentDocumentLink> initial = [SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'];
System.debug('  PDFs at start: ' + initial.size());

System.debug('======== STEP 1: Fill in StartDate + EndDate + ContractTerm (should trigger regen) ========');
Contract c1 = new Contract(Id = contractId, StartDate = Date.today(), ContractTerm = 12);
update c1;
List<ContentDocumentLink> step1 = [SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'];
System.debug('  PDFs after filling key data: ' + step1.size());
for (ContentDocumentLink l : step1) System.debug('    ' + l.ContentDocument.Title + ' | DocId=' + l.ContentDocumentId);
Id step1DocId = step1.isEmpty() ? null : step1[0].ContentDocumentId;

System.debug('======== STEP 2: Touch Description (should NOT trigger regen) ========');
update new Contract(Id = contractId, Description = 'Test desc ' + DateTime.now().format('HH:mm:ss'));
List<ContentDocumentLink> step2 = [SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'];
Id step2DocId = step2.isEmpty() ? null : step2[0].ContentDocumentId;
System.debug('  PDFs after Description: ' + step2.size() + ' | Same DocId? ' + (step1DocId == step2DocId));
System.assertEquals(step1DocId, step2DocId, 'Description change must NOT regen the PDF');

System.debug('======== STEP 3: Touch ContractTerm (should trigger regen) ========');
update new Contract(Id = contractId, ContractTerm = 24);
List<ContentDocumentLink> step3 = [SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'];
Id step3DocId = step3.isEmpty() ? null : step3[0].ContentDocumentId;
System.debug('  PDFs after ContractTerm: ' + step3.size() + ' | New DocId? ' + (step1DocId != step3DocId));
System.assertEquals(1, step3.size(), 'Should still be exactly one PDF (old deleted, new inserted)');
System.assertNotEquals(step1DocId, step3DocId, 'New PDF must have a different ContentDocumentId');

System.debug('======== ALL TESTS PASSED ========');
