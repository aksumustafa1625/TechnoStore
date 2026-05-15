trigger OrderTrigger on Order (before insert, before update) {
    new OrderTriggerHandler().run();
}
