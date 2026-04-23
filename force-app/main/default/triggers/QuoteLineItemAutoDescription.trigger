trigger QuoteLineItemAutoDescription on QuoteLineItem (before insert, before update) {
    // Auto-populate Description so createClmContract can build SalesContractLine.Name from Quote
    Set<Id> needProduct = new Set<Id>();
    for (QuoteLineItem q : Trigger.new) {
        if (String.isBlank(q.Description) && q.Product2Id != null) needProduct.add(q.Product2Id);
    }
    if (needProduct.isEmpty()) return;
    Map<Id, Product2> prodMap = new Map<Id, Product2>([SELECT Id, Name FROM Product2 WHERE Id IN :needProduct]);
    for (QuoteLineItem q : Trigger.new) {
        if (String.isBlank(q.Description) && q.Product2Id != null) {
            Product2 p = prodMap.get(q.Product2Id);
            if (p != null) q.Description = p.Name;
        }
    }
}
