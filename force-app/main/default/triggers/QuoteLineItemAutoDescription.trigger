trigger QuoteLineItemAutoDescription on QuoteLineItem (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    new QuoteLineItemTriggerHandler().run();
}
