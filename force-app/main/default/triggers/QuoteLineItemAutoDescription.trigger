trigger QuoteLineItemAutoDescription on QuoteLineItem (before insert, before update) {
    new QuoteLineItemTriggerHandler().run();
}
