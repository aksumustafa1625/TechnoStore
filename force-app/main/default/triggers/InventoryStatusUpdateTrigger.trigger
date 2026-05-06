trigger InventoryStatusUpdateTrigger on Inventory_Status_Update__e (after insert) {
    InventoryStatusUpdateTriggerHandler.handleAfterInsert(Trigger.new);
}
