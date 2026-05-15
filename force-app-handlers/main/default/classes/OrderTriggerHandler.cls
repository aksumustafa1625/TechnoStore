/**
 * Order trigger handler — Kevin O'Hara pattern.
 *
 * Responsibilities:
 *   - beforeInsert / beforeUpdate:
 *       Auto-populate BillToContactId, ShipToContactId, and Billing/Shipping
 *       address blocks from the related Account when they are blank. This
 *       prevents "missing required field" errors at Order activation when the
 *       upstream Quote → Order field mapping fails to copy these values.
 *
 * The handler is idempotent and safe — it only writes values when the target
 * field is null. If an admin/integration has already populated them, the
 * handler does not overwrite.
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

    /**
     * For each Order, if any of BillToContactId / ShipToContactId / Billing or
     * Shipping address fields are blank, copy them from the Account's primary
     * Contact (first by CreatedDate) and Account address.
     */
    private void backfillFromAccount(List<Order> orders) {
        // Collect Account IDs whose orders need backfilling
        Set<Id> accountIds = new Set<Id>();
        for (Order o : orders) {
            if (o.AccountId == null) continue;
            if (needsBackfill(o)) accountIds.add(o.AccountId);
        }
        if (accountIds.isEmpty()) return;

        // Load Account + first Contact in one round-trip
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

            // Primary contact = first contact on account
            Id primaryContactId = (a.Contacts != null && !a.Contacts.isEmpty()) ? a.Contacts[0].Id : null;

            // ----- Contact references -----
            if (o.BillToContactId == null && primaryContactId != null) o.BillToContactId = primaryContactId;
            if (o.ShipToContactId == null && primaryContactId != null) o.ShipToContactId = primaryContactId;

            // ----- Billing address (only fill blanks) -----
            if (String.isBlank(o.BillingStreet))     o.BillingStreet     = a.BillingStreet;
            if (String.isBlank(o.BillingCity))       o.BillingCity       = a.BillingCity;
            if (String.isBlank(o.BillingState))      o.BillingState      = a.BillingState;
            if (String.isBlank(o.BillingPostalCode)) o.BillingPostalCode = a.BillingPostalCode;
            if (String.isBlank(o.BillingCountry))    o.BillingCountry    = a.BillingCountry;

            // ----- Shipping address (only fill blanks) -----
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
}
