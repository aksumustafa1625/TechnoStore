Integer envCount = [SELECT COUNT() FROM DocumentEnvelope];
Integer recCount = [SELECT COUNT() FROM DocumentRecipient];
System.debug('Total Envelopes: ' + envCount + ' | Total Recipients: ' + recCount);

for (DocumentEnvelope e : [SELECT Id, Name, Status FROM DocumentEnvelope ORDER BY CreatedDate DESC LIMIT 5]) {
    System.debug('ENV ' + e.Id + ' | ' + e.Name + ' | ' + e.Status);
}

for (DocumentRecipient r : [SELECT Id, RecipientName, RecipientId, Email, LegalName, Status, Type FROM DocumentRecipient ORDER BY CreatedDate DESC LIMIT 10]) {
    System.debug('REC | name=' + r.RecipientName + ' | recipientId=' + r.RecipientId + ' | email=' + r.Email + ' | legal=' + r.LegalName + ' | status=' + r.Status + ' | type=' + r.Type);
}
