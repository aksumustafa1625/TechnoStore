// Simpler test: take a snapshot of the current PDF DocId, do two specific updates,
// and observe whether the DocId changed (= flow fired) or stayed (= flow didn't fire).

Id contractId = [SELECT Id FROM Contract WHERE ContractNumber = '00000300' LIMIT 1].Id;

Id snapshotDocId = [SELECT ContentDocumentId FROM ContentDocumentLink
                    WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'
                    LIMIT 1].ContentDocumentId;
System.debug('Initial PDF DocId: ' + snapshotDocId);

// CASE A: Description-only update — flow should NOT fire (Description not in ISCHANGED list)
update new Contract(Id = contractId, Description = 'Smart trigger test ' + DateTime.now().getTime());
Id afterDescDocId = [SELECT ContentDocumentId FROM ContentDocumentLink
                     WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'
                     LIMIT 1].ContentDocumentId;
System.debug('After Description update, DocId: ' + afterDescDocId + ' | Same? ' + (afterDescDocId == snapshotDocId));

// CASE B: ContractTerm change — flow SHOULD fire, old PDF deleted, new one inserted
Integer currentTerm = [SELECT ContractTerm FROM Contract WHERE Id = :contractId].ContractTerm;
update new Contract(Id = contractId, ContractTerm = (currentTerm == 12 ? 24 : 12));
Id afterTermDocId = [SELECT ContentDocumentId FROM ContentDocumentLink
                     WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'
                     LIMIT 1].ContentDocumentId;
Integer pdfCount = [SELECT COUNT() FROM ContentDocumentLink
                    WHERE LinkedEntityId = :contractId AND ContentDocument.Title LIKE 'TechnoStore_MSA_%'];
System.debug('After ContractTerm update, DocId: ' + afterTermDocId + ' | New? ' + (afterTermDocId != afterDescDocId) + ' | PDF count: ' + pdfCount);

// Summary
System.debug('=========');
System.debug('PASS: Description does not trigger regen? ' + (afterDescDocId == snapshotDocId));
System.debug('PASS: ContractTerm triggers regen?       ' + (afterTermDocId != afterDescDocId));
System.debug('PASS: Exactly one PDF after regen?       ' + (pdfCount == 1));
