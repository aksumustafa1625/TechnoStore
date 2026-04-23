trigger OrderItemAutoDescription on OrderItem (before insert, before update) {
    // Auto-populate Description so createClmContract can build SalesContractLine.Name
    Set<Id> needProduct = new Set<Id>();
    for (OrderItem oi : Trigger.new) {
        if (String.isBlank(oi.Description) && oi.Product2Id != null) needProduct.add(oi.Product2Id);
    }
    if (needProduct.isEmpty()) return;
    Map<Id, Product2> prodMap = new Map<Id, Product2>([SELECT Id, Name FROM Product2 WHERE Id IN :needProduct]);
    for (OrderItem oi : Trigger.new) {
        if (String.isBlank(oi.Description) && oi.Product2Id != null) {
            Product2 p = prodMap.get(oi.Product2Id);
            if (p != null) oi.Description = p.Name;
        }
    }
}
