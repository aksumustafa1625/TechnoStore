trigger InvoiceTrigger on Invoice (after update) {
    new InvoiceTriggerHandler().run();
}
