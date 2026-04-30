/**
 * Backend for the Revenue Pulse LWC. Returns total revenue plus the most-recent
 * Service Activations (one record per Stripe-paid Invoice). Cacheable so the
 * Lightning Data Service can stream updates efficiently.
 */
public with sharing class RevenuePulseController {

    public class RecentActivation {
        @AuraEnabled public Id activationId;
        @AuraEnabled public String activationName;
        @AuraEnabled public String invoiceReference;
        @AuraEnabled public String serviceType;
        @AuraEnabled public String activationStatus;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Datetime activationDate;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Boolean slackNotified;
        @AuraEnabled public String sendcloudCarrier;
        @AuraEnabled public String sendcloudParcelId;
    }

    public class PulseData {
        @AuraEnabled public Decimal totalRevenue;
        @AuraEnabled public Integer paidCount;
        @AuraEnabled public Decimal todayRevenue;
        @AuraEnabled public Integer todayCount;
        @AuraEnabled public List<RecentActivation> recentActivations;
        @AuraEnabled public Datetime serverTime;
    }

    @AuraEnabled(cacheable=true)
    public static PulseData getPulseData() {
        PulseData data = new PulseData();
        data.serverTime = Datetime.now();
        data.recentActivations = new List<RecentActivation>();
        data.totalRevenue = 0;
        data.paidCount = 0;
        data.todayRevenue = 0;
        data.todayCount = 0;

        Datetime startOfToday = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));

        for (AggregateResult ar : [
            SELECT COUNT(Id) cnt, SUM(Amount__c) total
            FROM Service_Activation__c
            WHERE Activation_Status__c = 'Active'
        ]) {
            data.paidCount = (Integer) ar.get('cnt');
            data.totalRevenue = (Decimal) ar.get('total');
            if (data.totalRevenue == null) data.totalRevenue = 0;
        }

        for (AggregateResult ar : [
            SELECT COUNT(Id) cnt, SUM(Amount__c) total
            FROM Service_Activation__c
            WHERE Activation_Status__c = 'Active'
              AND Activation_Date__c >= :startOfToday
        ]) {
            data.todayCount = (Integer) ar.get('cnt');
            data.todayRevenue = (Decimal) ar.get('total');
            if (data.todayRevenue == null) data.todayRevenue = 0;
        }

        for (Service_Activation__c sa : [
            SELECT Id, Name, Invoice_Reference__c, Service_Type__c,
                   Activation_Status__c, Amount__c, Activation_Date__c, Tracking_Number__c,
                   Slack_Notified__c, Sendcloud_Carrier__c, Sendcloud_Parcel_Id__c
            FROM Service_Activation__c
            WHERE Activation_Status__c = 'Active'
            ORDER BY Activation_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 10
        ]) {
            RecentActivation ra = new RecentActivation();
            ra.activationId = sa.Id;
            ra.activationName = sa.Name;
            ra.invoiceReference = sa.Invoice_Reference__c;
            ra.serviceType = sa.Service_Type__c;
            ra.activationStatus = sa.Activation_Status__c;
            ra.amount = sa.Amount__c == null ? 0 : sa.Amount__c;
            ra.activationDate = sa.Activation_Date__c;
            ra.trackingNumber = sa.Tracking_Number__c;
            ra.slackNotified = sa.Slack_Notified__c;
            ra.sendcloudCarrier = sa.Sendcloud_Carrier__c;
            ra.sendcloudParcelId = sa.Sendcloud_Parcel_Id__c;
            data.recentActivations.add(ra);
        }

        return data;
    }
}
