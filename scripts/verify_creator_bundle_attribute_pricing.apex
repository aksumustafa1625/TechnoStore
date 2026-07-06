Quote sourceQuote = [
    SELECT OpportunityId, Pricebook2Id
    FROM Quote
    WHERE Id = '0Q0aj000002hDwyCAE'
    LIMIT 1
];

Quote testQuote = new Quote(
    Name = 'Codex Creator Bundle Verification ' + String.valueOf(DateTime.now().getTime()),
    OpportunityId = sourceQuote.OpportunityId,
    Pricebook2Id = sourceQuote.Pricebook2Id,
    ExpirationDate = Date.today().addDays(30),
    Status = 'Draft'
);
insert testQuote;

PricebookEntry parentPbe = [
    SELECT Id, UnitPrice
    FROM PricebookEntry
    WHERE Product2Id = '01taj00000Qp7IHAAZ'
      AND Pricebook2Id = :sourceQuote.Pricebook2Id
      AND IsActive = true
      AND ProductSellingModelId = null
    LIMIT 1
];

QuoteLineItem parent = new QuoteLineItem(
    QuoteId = testQuote.Id,
    Product2Id = '01taj00000Qp7IHAAZ',
    PricebookEntryId = parentPbe.Id,
    Quantity = 1,
    UnitPrice = parentPbe.UnitPrice
);
insert parent;

Database.insertImmediate(new List<QuoteLineItemAttribute>{
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXJAA0',
        AttributePicklistValueId = '0v6aj000000G24WAAS',
        AttributeValue = 'RAM 16GB',
        ExternalId = 'creator-memory-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXNAA0',
        AttributePicklistValueId = '0v6aj000000G24iAAC',
        AttributeValue = 'SSD Hard Drive 512GB',
        ExternalId = 'creator-storage-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXMAA0',
        AttributePicklistValueId = '0v6aj000000G24cAAC',
        AttributeValue = 'i7-CPU 4.7GHz',
        ExternalId = 'creator-processor-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXHAA0',
        AttributePicklistValueId = '0v6aj000000G24RAAS',
        AttributeValue = '15 Inch',
        ExternalId = 'creator-screen-' + parent.Id
    )
});

parent.Description = 'Creator attribute pricing verification ' + String.valueOf(DateTime.now().getTime());
update parent;

QuoteLineItem refreshedParent = [
    SELECT Id, UnitPrice, TotalPrice
    FROM QuoteLineItem
    WHERE Id = :parent.Id
];

System.debug('CREATOR_VERIFY_QUOTE_ID=' + testQuote.Id);
System.debug('CREATOR_PARENT_UNIT_PRICE=' + refreshedParent.UnitPrice);
System.debug('CREATOR_PARENT_TOTAL_PRICE=' + refreshedParent.TotalPrice);
