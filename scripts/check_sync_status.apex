for (ContextDefinitionSync cds : [SELECT Id, ContextDefinitionName, Status, StartDateTime, EndDateTime, SynchronizationInformation
                                  FROM ContextDefinitionSync
                                  WHERE Id IN ('1Giaj000000DUmfCAG','1Giaj000000DUmgCAG')]) {
    System.debug(cds);
}
