/**
 * Trigger handler for OrderItem.
 *
 * Auto-populates Description from Product2.Name so that
 * createClmContract can build SalesContractLine.Name when an Order is
 * converted to a Contract via Revenue Cloud's CLM flow.
 *
 * Extends Kevin O'Hara TriggerHandler framework.
 */
public with sharing class OrderItemTriggerHandler extends TriggerHandler {

    @TestVisible
    private List<OrderItem> records {
        get { return (List<OrderItem>) Trigger.new; }
    }

    protected override void beforeInsert() {
        autoPopulateDescription();
    }

    protected override void beforeUpdate() {
        autoPopulateDescription();
    }

    private void autoPopulateDescription() {
        Set<Id> needProduct = new Set<Id>();
        for (OrderItem oi : records) {
            if (String.isBlank(oi.Description) && oi.Product2Id != null) needProduct.add(oi.Product2Id);
        }
        if (needProduct.isEmpty()) return;
        Map<Id, Product2> prodMap = new Map<Id, Product2>([
            SELECT Id, Name FROM Product2 WHERE Id IN :needProduct
        ]);
        for (OrderItem oi : records) {
            if (String.isBlank(oi.Description) && oi.Product2Id != null) {
                Product2 p = prodMap.get(oi.Product2Id);
                if (p != null) oi.Description = p.Name;
            }
        }
    }
}
