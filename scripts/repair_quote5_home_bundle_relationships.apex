Id quoteId = '0Q0aj000002hDwzCAE';
Id parentProductId = '01taj00000Qp7IFAAZ';

QuoteLineItem parentLine = [
    SELECT Id, Product2Id, QuoteId
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId AND Product2Id = :parentProductId
    LIMIT 1
];

Map<Id, ProductRelatedComponent> componentByChildProduct = new Map<Id, ProductRelatedComponent>();
for (ProductRelatedComponent component : [
    SELECT Id, ChildProductId, ProductRelationshipTypeId, DoesBundlePriceIncludeChild, QuantityScaleMethod
    FROM ProductRelatedComponent
    WHERE ParentProductId = :parentProductId
]) {
    componentByChildProduct.put(component.ChildProductId, component);
}

List<QuoteLineItem> childLines = [
    SELECT Id, Product2Id, ParentQuoteLineItemId
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId
    AND Product2Id IN :componentByChildProduct.keySet()
];

Set<Id> alreadyRelatedChildLineIds = new Set<Id>();
for (QuoteLineRelationship existingRel : [
    SELECT AssociatedQuoteLineId
    FROM QuoteLineRelationship
    WHERE QuoteId = :quoteId
    AND MainQuoteLineId = :parentLine.Id
]) {
    alreadyRelatedChildLineIds.add(existingRel.AssociatedQuoteLineId);
}

List<QuoteLineRelationship> relationshipsToInsert = new List<QuoteLineRelationship>();
for (QuoteLineItem childLine : childLines) {
    ProductRelatedComponent component = componentByChildProduct.get(childLine.Product2Id);
    if (component == null || alreadyRelatedChildLineIds.contains(childLine.Id)) {
        continue;
    }

    relationshipsToInsert.add(new QuoteLineRelationship(
        MainQuoteLineId = parentLine.Id,
        AssociatedQuoteLineId = childLine.Id,
        RootQuoteLineId = parentLine.Id,
        ProductRelatedComponentId = component.Id,
        ProductRelationshipTypeId = component.ProductRelationshipTypeId,
        AssociatedQuoteLinePricing = component.DoesBundlePriceIncludeChild
            ? 'IncludedInBundlePrice'
            : 'NotIncludedInBundlePrice',
        AssociatedQuantScaleMethod = 'Constant'
    ));

}

if (!relationshipsToInsert.isEmpty()) {
    insert relationshipsToInsert;
}

System.debug('Inserted QuoteLineRelationship rows: ' + relationshipsToInsert.size());
