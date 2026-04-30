trigger OrderItemAutoDescription on OrderItem (before insert, before update) {
    new OrderItemTriggerHandler().run();
}
