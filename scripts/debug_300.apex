// Minimal smoke test — just query and update Description on contract 00000300
Contract c = [SELECT Id, ContractNumber, Status FROM Contract WHERE ContractNumber = '00000300' LIMIT 1];
System.debug('Found: ' + c.Id + ' | ' + c.ContractNumber + ' | ' + c.Status);

try {
    update new Contract(Id = c.Id, Description = 'Smoke test ' + DateTime.now().format('HH:mm:ss'));
    System.debug('Update OK');
} catch (Exception e) {
    System.debug('Update FAILED: ' + e.getTypeName() + ' — ' + e.getMessage());
}
