/**
 * Order trigger handler — Kevin O'Hara pattern.
 *
 * Responsibilities:
 *   - beforeInsert / beforeUpdate:
 *       Auto-populate BillToContactId, ShipToContactId, and Billing/Shipping
 *       address blocks from the related Account when they are blank. Prevents
 *       "missing required field" errors at Order activation when the upstream
 *       Quote → Order field mapping fails to copy these values.
 *
 *   - afterUpdate:
 *       When Order.Status transitions Draft → Activated, create one Asset per
 *       OrderItem. This is the B2C / transactional Pattern 1 — appropriate for
 *       one-time products (workstations, monitors, accessories) where legal
 *       ownership transfers at order activation, not at contract signing.
 *
 * Industry context: Pattern 1 (Asset on Order Activation) is standard for
 * direct-to-consumer + one-time B2B sales. Pattern 2 (Asset on Contract
 * Activation) is standard for B2B with negotiated contracts. TechnoStore
 * uses Pattern 1 because its product catalog is currently one-time hardware
 * (no subscriptions, no negotiated multi-year contracts).
 *
 * Bypass: TriggerHandler.bypass('OrderTriggerHandler') for bulk data loads.
 */
public with sharing class OrderTriggerHandler extends TriggerHandler {

    protected override void beforeInsert() {
        backfillFromAccount((List<Order>) Trigger.new);
    }

    protected override void beforeUpdate() {
        backfillFromAccount((List<Order>) Trigger.new);
    }

    protected override void afterUpdate() {
        Set<Id> ordersJustActivated = new Set<Id>();
        for (Order o : (List<Order>) Trigger.new) {
            Order oldOrder = (Order) Trigger.oldMap.get(o.Id);
            // Status transition: anything → Activated
            if (o.Status == 'Activated' && oldOrder.Status != 'Activated') {
                ordersJustActivated.add(o.Id);
            }
        }
        if (!ordersJustActivated.isEmpty()) {
            createAssetsForActivatedOrders(ordersJustActivated);
        }
    }

    // ============================================================
    // Backfill: populate Contact + Address fields from Account
    // ============================================================
    private void backfillFromAccount(List<Order> orders) {
        Set<Id> accountIds = new Set<Id>();
        for (Order o : orders) {
            if (o.AccountId == null) continue;
            if (needsBackfill(o)) accountIds.add(o.AccountId);
        }
        if (accountIds.isEmpty()) return;

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, Name,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   (SELECT Id FROM Contacts ORDER BY CreatedDate ASC LIMIT 1)
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Order o : orders) {
            if (o.AccountId == null) continue;
            Account a = accountsById.get(o.AccountId);
            if (a == null) continue;

            Id primaryContactId = (a.Contacts != null && !a.Contacts.isEmpty()) ? a.Contacts[0].Id : null;

            if (o.BillToContactId == null && primaryContactId != null) o.BillToContactId = primaryContactId;
            if (o.ShipToContactId == null && primaryContactId != null) o.ShipToContactId = primaryContactId;

            if (String.isBlank(o.BillingStreet))     o.BillingStreet     = a.BillingStreet;
            if (String.isBlank(o.BillingCity))       o.BillingCity       = a.BillingCity;
            if (String.isBlank(o.BillingState))      o.BillingState      = a.BillingState;
            if (String.isBlank(o.BillingPostalCode)) o.BillingPostalCode = a.BillingPostalCode;
            if (String.isBlank(o.BillingCountry))    o.BillingCountry    = a.BillingCountry;

            String shipStreet     = String.isNotBlank(a.ShippingStreet)     ? a.ShippingStreet     : a.BillingStreet;
            String shipCity       = String.isNotBlank(a.ShippingCity)       ? a.ShippingCity       : a.BillingCity;
            String shipState      = String.isNotBlank(a.ShippingState)      ? a.ShippingState      : a.BillingState;
            String shipPostalCode = String.isNotBlank(a.ShippingPostalCode) ? a.ShippingPostalCode : a.BillingPostalCode;
            String shipCountry    = String.isNotBlank(a.ShippingCountry)    ? a.ShippingCountry    : a.BillingCountry;

            if (String.isBlank(o.ShippingStreet))     o.ShippingStreet     = shipStreet;
            if (String.isBlank(o.ShippingCity))       o.ShippingCity       = shipCity;
            if (String.isBlank(o.ShippingState))      o.ShippingState      = shipState;
            if (String.isBlank(o.ShippingPostalCode)) o.ShippingPostalCode = shipPostalCode;
            if (String.isBlank(o.ShippingCountry))    o.ShippingCountry    = shipCountry;
        }
    }

    private Boolean needsBackfill(Order o) {
        return o.BillToContactId == null
            || o.ShipToContactId == null
            || String.isBlank(o.BillingStreet)
            || String.isBlank(o.BillingCity)
            || String.isBlank(o.ShippingStreet)
            || String.isBlank(o.ShippingCity);
    }

    // ============================================================
    // Asset creation on Order Activation (Pattern 1 — transactional)
    // ============================================================
    private static void createAssetsForActivatedOrders(Set<Id> orderIds) {
        // Query OrderItems with all data needed to mint Assets
        List<OrderItem> orderItems = [
            SELECT Id, OrderId,
                   Order.AccountId, Order.BillToContactId, Order.EffectiveDate, Order.OrderNumber,
                   Product2Id, Product2.Name, Product2.ProductCode,
                   Quantity, UnitPrice, TotalPrice
            FROM OrderItem
            WHERE OrderId IN :orderIds
            AND Product2Id != null
        ];

        if (orderItems.isEmpty()) return;

        // Idempotency: skip OrderItems that already have a linked Asset for this Account+Product
        // (prevents duplicate assets if Order re-activated)
        Set<Id> accountIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (OrderItem oi : orderItems) {
            accountIds.add(oi.Order.AccountId);
            productIds.add(oi.Product2Id);
        }
        Set<String> existingKeys = new Set<String>();
        for (Asset existing : [
            SELECT AccountId, Product2Id, Description
            FROM Asset
            WHERE AccountId IN :accountIds
            AND Product2Id IN :productIds
        ]) {
            existingKeys.add(existing.AccountId + '|' + existing.Product2Id + '|' + (existing.Description == null ? '' : existing.Description));
        }

        List<Asset> assetsToCreate = new List<Asset>();
        for (OrderItem oi : orderItems) {
            String dedupKey = oi.Order.AccountId + '|' + oi.Product2Id + '|Order ' + oi.Order.OrderNumber;
            if (existingKeys.contains(dedupKey)) continue;

            Asset a = new Asset(
                Name         = oi.Product2.Name,
                AccountId    = oi.Order.AccountId,
                ContactId    = oi.Order.BillToContactId,
                Product2Id   = oi.Product2Id,
                Quantity     = oi.Quantity,
                Price        = oi.UnitPrice,
                Status       = 'Purchased',
                PurchaseDate = oi.Order.EffectiveDate != null ? oi.Order.EffectiveDate : Date.today(),
                InstallDate  = Date.today(),
                Description  = 'Order ' + oi.Order.OrderNumber
            );
            assetsToCreate.add(a);
        }

        if (!assetsToCreate.isEmpty()) {
            Database.SaveResult[] results = Database.insert(assetsToCreate, false);
            Integer ok = 0;
            for (Database.SaveResult r : results) {
                if (r.isSuccess()) ok++;
                else System.debug(LoggingLevel.WARN, 'Asset create failed: ' + r.getErrors()[0].getMessage());
            }
            System.debug('Order Activation → Created ' + ok + ' Asset(s) of ' + assetsToCreate.size() + ' attempted');
        }
    }
}
