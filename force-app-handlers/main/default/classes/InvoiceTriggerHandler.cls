/**
 * Invoice trigger handler — Kevin O'Hara pattern.
 *
 * Responsibility (afterUpdate):
 *   When an Invoice's Stripe_Payment_Status__c transitions to 'Paid' (the Stripe webhook →
 *   Mule → Invoice flow marks it Paid), automatically publish the invoice to lexoffice so a
 *   Rechnung is created in the German cloud accounting system in real time (ADR-030).
 *
 * This is the event-driven counterpart to the manual button: in production, payment posting
 * should auto-propagate to accounting without a human click. Mirrors OrderTriggerHandler, which
 * publishes Order_Activated__e on Status → Activated.
 *
 * Idempotency: only fires when the invoice is not already Lexoffice_Status__c = 'Published',
 * so re-saves / repeated webhook updates don't create duplicate lexoffice invoices.
 *
 * Async: calls LexofficeInvoiceService.publishAsync (@future callout) so the HTTP callout runs
 * in a fresh transaction after the trigger's DML commits (avoids "uncommitted work pending").
 *
 * Bypass: TriggerHandler.bypass('InvoiceTriggerHandler') for bulk data loads.
 */
public with sharing class InvoiceTriggerHandler extends TriggerHandler {

    protected override void afterUpdate() {
        Set<Id> justPaid = new Set<Id>();
        for (Invoice inv : (List<Invoice>) Trigger.new) {
            Invoice old = (Invoice) Trigger.oldMap.get(inv.Id);
            if (inv.Stripe_Payment_Status__c == 'Paid'
                    && old.Stripe_Payment_Status__c != 'Paid'
                    && inv.Lexoffice_Status__c != 'Published') {
                justPaid.add(inv.Id);
            }
        }
        if (!justPaid.isEmpty()) {
            LexofficeInvoiceService.publishAsync(justPaid);
        }
    }
}
