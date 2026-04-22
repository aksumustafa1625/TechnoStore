Opportunity opp = [SELECT Id, Pricebook2Id, AccountId FROM Opportunity WHERE AccountId != null LIMIT 1];
Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

Quote q = new Quote(
    Name = 'CTX_TEST_' + DateTime.now().format('HHmmss'),
    OpportunityId = opp.Id,
    Pricebook2Id = opp.Pricebook2Id != null ? opp.Pricebook2Id : pb.Id,
    Status = 'Draft'
);
insert q;

PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :q.Pricebook2Id AND IsActive = true LIMIT 1];

QuoteLineItem qli = new QuoteLineItem(
    QuoteId = q.Id,
    PricebookEntryId = pbe.Id,
    Product2Id = pbe.Product2Id,
    Quantity = 1,
    UnitPrice = pbe.UnitPrice
);
insert qli;

System.debug('QUOTE_ID=' + q.Id);
System.debug('QLI_ID=' + qli.Id);
System.debug('QLI_LINE_NUMBER=' + [SELECT LineNumber FROM QuoteLineItem WHERE Id = :qli.Id].LineNumber);