trigger OrderTrigger on Order (before insert, before update, after update) {
    new OrderTriggerHandler().run();
}
