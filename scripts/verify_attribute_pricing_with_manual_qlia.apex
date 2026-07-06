Id testQuoteId = '0Q0aj000002hajpCAA';

QuoteLineItem parent = [
    SELECT Id, Description
    FROM QuoteLineItem
    WHERE QuoteId = :testQuoteId
      AND Product2Id = '01taj00000Qp7IFAAZ'
    LIMIT 1
];

List<QuoteLineItemAttribute> attrs = new List<QuoteLineItemAttribute>{
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXJAA0',
        AttributePicklistValueId = '0v6aj000000G24VAAS',
        AttributeValue = 'RAM 64GB',
        ExternalId = 'codex-memory-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXNAA0',
        AttributePicklistValueId = '0v6aj000000G24jAAC',
        AttributeValue = 'SSD Hard Drive 2TB',
        ExternalId = 'codex-storage-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXMAA0',
        AttributePicklistValueId = '0v6aj000000G24cAAC',
        AttributeValue = 'i7-CPU 4.7GHz',
        ExternalId = 'codex-processor-' + parent.Id
    ),
    new QuoteLineItemAttribute(
        QuoteLineItemId = parent.Id,
        AttributeDefinitionId = '0tjaj000000FbXHAA0',
        AttributePicklistValueId = '0v6aj000000G24OAAS',
        AttributeValue = '27 Inch',
        ExternalId = 'codex-screen-' + parent.Id
    )
};
Database.insertImmediate(attrs);

parent.Description = 'Attribute pricing verification ' + String.valueOf(DateTime.now().getTime());
update parent;

QuoteLineItem refreshed = [
    SELECT Id, UnitPrice, TotalPrice
    FROM QuoteLineItem
    WHERE Id = :parent.Id
];
System.debug('ATTR_VERIFY_PARENT_UNIT_PRICE=' + refreshed.UnitPrice);
System.debug('ATTR_VERIFY_PARENT_TOTAL_PRICE=' + refreshed.TotalPrice);
