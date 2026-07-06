Set<Id> quoteIds = new Set<Id>{
    '0Q0aj000002hDwyCAE',
    '0Q0aj000002hDwzCAE'
};

List<QuoteLineItem> qlis = [
    SELECT Id, QuoteId, Product2Id, Product2.ProductCode, Product2.Type
    FROM QuoteLineItem
    WHERE QuoteId IN :quoteIds
];

Map<Id, QuoteLineItem> parentByQuote = new Map<Id, QuoteLineItem>();
Map<String, QuoteLineItem> childByQuoteAndProduct = new Map<String, QuoteLineItem>();
Set<Id> parentProductIds = new Set<Id>();
Set<Id> parentQuoteLineIds = new Set<Id>();

for (QuoteLineItem qli : qlis) {
    if (qli.Product2.Type == 'Bundle') {
        parentByQuote.put(qli.QuoteId, qli);
        parentProductIds.add(qli.Product2Id);
        parentQuoteLineIds.add(qli.Id);
    } else {
        childByQuoteAndProduct.put(qli.QuoteId + '|' + qli.Product2Id, qli);
    }
}

Map<String, ProductRelatedComponent> componentByParentAndChild = new Map<String, ProductRelatedComponent>();
for (ProductRelatedComponent component : [
    SELECT Id, ParentProductId, ChildProductId, DoesBundlePriceIncludeChild, ProductRelationshipTypeId
    FROM ProductRelatedComponent
    WHERE ParentProductId IN :parentProductIds
]) {
    componentByParentAndChild.put(component.ParentProductId + '|' + component.ChildProductId, component);
}

Set<String> existingRelationshipKeys = new Set<String>();
for (QuoteLineRelationship existing : [
    SELECT MainQuoteLineId, AssociatedQuoteLineId
    FROM QuoteLineRelationship
    WHERE MainQuoteLineId IN :parentQuoteLineIds
]) {
    existingRelationshipKeys.add(existing.MainQuoteLineId + '|' + existing.AssociatedQuoteLineId);
}

List<QuoteLineRelationship> relationshipsToInsert = new List<QuoteLineRelationship>();
for (QuoteLineItem parent : parentByQuote.values()) {
    for (String childKey : childByQuoteAndProduct.keySet()) {
        if (!childKey.startsWith(String.valueOf(parent.QuoteId) + '|')) continue;

        QuoteLineItem child = childByQuoteAndProduct.get(childKey);
        ProductRelatedComponent component = componentByParentAndChild.get(parent.Product2Id + '|' + child.Product2Id);
        if (component == null) continue;

        String relationshipKey = parent.Id + '|' + child.Id;
        if (existingRelationshipKeys.contains(relationshipKey)) continue;

        QuoteLineRelationship relationship = new QuoteLineRelationship();
        relationship.MainQuoteLineId = parent.Id;
        relationship.AssociatedQuoteLineId = child.Id;
        relationship.RootQuoteLineId = parent.Id;
        relationship.ProductRelatedComponentId = component.Id;
        relationship.ProductRelationshipTypeId = component.ProductRelationshipTypeId;
        relationship.AssociatedQuoteLinePricing = component.DoesBundlePriceIncludeChild == true
            ? 'IncludedInBundlePrice'
            : 'NotIncludedInBundlePrice';
        relationship.AssociatedQuantScaleMethod = 'Constant';
        relationshipsToInsert.add(relationship);
        existingRelationshipKeys.add(relationshipKey);
    }
}

if (!relationshipsToInsert.isEmpty()) {
    insert relationshipsToInsert;
}

System.debug('NATIVE_BUNDLE_RELATIONSHIPS_INSERTED=' + relationshipsToInsert.size());
for (QuoteLineRelationship relationship : relationshipsToInsert) {
    System.debug('NATIVE_BUNDLE_RELATIONSHIP ' + relationship.MainQuoteLineId + ' -> ' + relationship.AssociatedQuoteLineId + ' pricing=' + relationship.AssociatedQuoteLinePricing);
}
