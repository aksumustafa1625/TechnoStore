// Inspect DecisionTable runtime behavior — does Product_Disqualification DT
// have associated record set / dataset and is it actually wired to filter at runtime?

Id disqualDtId = '0lDaj000000DanPEAS';

System.debug('======== DecisionTable detail ========');
for (DecisionTable dt : [SELECT FIELDS(STANDARD) FROM DecisionTable WHERE Id = :disqualDtId LIMIT 1]) {
    System.debug(dt);
}

System.debug('======== DecisionTableDataset (its source data) ========');
for (DecisionTableDataset dtds : [SELECT FIELDS(STANDARD) FROM DecisionTableDataset WHERE DecisionTableId = :disqualDtId LIMIT 10]) {
    System.debug(dtds);
}

System.debug('======== DecisionTableDatasetLink ========');
for (DecisionTableDatasetLink dtdl : [SELECT FIELDS(STANDARD) FROM DecisionTableDatasetLink WHERE DecisionTableId = :disqualDtId LIMIT 20]) {
    System.debug(dtdl);
}

System.debug('======== DecisionTableRecordset (sample) ========');
for (DecisionTableRecordSet dtrs : [SELECT FIELDS(STANDARD) FROM DecisionTableRecordSet WHERE DecisionTableId = :disqualDtId LIMIT 5]) {
    System.debug(dtrs);
}

System.debug('======== Existing PDQ records for POS01 (raw) ========');
Id posId = [SELECT Id FROM Product2 WHERE ProductCode = 'POS01' LIMIT 1].Id;
for (ProductDisqualification pdq : [SELECT Id, Industry__c, IsDisqualified FROM ProductDisqualification WHERE ProductId = :posId AND Industry__c = 'Technology']) {
    System.debug('Tech PDQ for POS01: ' + pdq);
}
