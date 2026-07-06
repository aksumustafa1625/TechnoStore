Quote sourceQuote = [
    SELECT OpportunityId, Pricebook2Id
    FROM Quote
    WHERE Id = '0Q0aj000002hDwzCAE'
    LIMIT 1
];

Quote testQuote = new Quote();
testQuote.Name = 'Codex Bundle Verification ' + String.valueOf(DateTime.now().getTime());
testQuote.OpportunityId = sourceQuote.OpportunityId;
testQuote.Pricebook2Id = sourceQuote.Pricebook2Id;
testQuote.ExpirationDate = Date.today().addDays(30);
testQuote.Status = 'Draft';
insert testQuote;

PricebookEntry parentPbe = [
    SELECT Id, UnitPrice
    FROM PricebookEntry
    WHERE Product2Id = '01taj00000Qp7IFAAZ'
      AND Pricebook2Id = :sourceQuote.Pricebook2Id
      AND IsActive = true
      AND ProductSellingModelId = null
    LIMIT 1
];

insert new QuoteLineItem(
    QuoteId = testQuote.Id,
    Product2Id = '01taj00000Qp7IFAAZ',
    PricebookEntryId = parentPbe.Id,
    Quantity = 1,
    UnitPrice = parentPbe.UnitPrice
);

System.debug('BUNDLE_VERIFY_QUOTE_ID=' + testQuote.Id);
