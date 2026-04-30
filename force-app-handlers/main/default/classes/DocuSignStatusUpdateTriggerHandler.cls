/**
 * Trigger handler for DocuSign_Status_Update__e Platform Event.
 * Maps DocuSign envelope completion status to Contract.Status.
 *
 * Extends Kevin O'Hara TriggerHandler framework.
 */
public with sharing class DocuSignStatusUpdateTriggerHandler extends TriggerHandler {

    @TestVisible
    private List<DocuSign_Status_Update__e> events {
        get { return (List<DocuSign_Status_Update__e>) Trigger.new; }
    }

    protected override void afterInsert() {
        Map<String, String> envelopeToStatus = new Map<String, String>();
        for (DocuSign_Status_Update__e e : events) {
            if (String.isBlank(e.Envelope_Id__c) || String.isBlank(e.DocuSign_Status__c)) continue;
            String s = e.DocuSign_Status__c.toLowerCase();
            String mapped;
            if (s == 'completed') mapped = 'Signed';
            else if (s == 'declined') mapped = 'Signature Declined';
            else if (s == 'voided') mapped = 'Canceled';
            if (mapped != null) envelopeToStatus.put(e.Envelope_Id__c, mapped);
        }
        if (envelopeToStatus.isEmpty()) return;

        List<Contract> contracts = [
            SELECT Id, DocuSign_Envelope_Id__c, Status FROM Contract
            WHERE DocuSign_Envelope_Id__c IN :envelopeToStatus.keySet()
        ];
        for (Contract c : contracts) {
            c.Status = envelopeToStatus.get(c.DocuSign_Envelope_Id__c);
        }
        if (!contracts.isEmpty()) update contracts;
    }
}
