trigger DocuSignStatusUpdateTrigger on DocuSign_Status_Update__e (after insert) {
    new DocuSignStatusUpdateTriggerHandler().run();
}
