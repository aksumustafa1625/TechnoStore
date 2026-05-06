trigger DocumentRecipientAutoFillSignerName on DocumentRecipient (before insert, before update) {
    new DocumentRecipientTriggerHandler().run();
}
