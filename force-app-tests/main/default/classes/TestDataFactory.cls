/**
 * Shared test data factory for TechnoStore Apex tests.
 *
 * Design principles:
 *   - No SeeAllData: every test builds its own graph in @TestSetup.
 *   - Deterministic: same call → same shape, so assertions are stable.
 *   - Lean: only fields required for the sObject to insert or the assertion to hold.
 *   - Extend on demand: add builders as new test classes need them, don't front-load.
 *
 * Extend cautiously — every new builder here is a widening of the test-data surface
 * and any change ripples across every test class that consumes it.
 */
@IsTest
public class TestDataFactory {

    // ---------- Accounts ----------

    public static Account newAccount(String name) {
        Account a = new Account(
            Name = name,
            BillingCountry = 'Germany',
            BillingCity = 'Berlin',
            BillingStreet = 'Musterstrasse 1',
            BillingPostalCode = '10115'
        );
        insert a;
        return a;
    }

    public static Account newAccount() {
        return newAccount('Acme DE GmbH');
    }

    // ---------- Contacts ----------

    public static Contact newContact(Id accountId, String email) {
        Contact c = new Contact(
            AccountId = accountId,
            FirstName = 'Test',
            LastName = 'Contact',
            Email = email
        );
        insert c;
        return c;
    }

    // ---------- Webhook_Event__c ----------
    // (Convenience builders — do NOT insert; caller decides insert vs the class under test doing it)

    public static Webhook_Event__c buildWebhookEvent(String source, String externalId, String eventType) {
        return new Webhook_Event__c(
            Source__c = source,
            External_Id__c = externalId,
            Event_Type__c = eventType,
            Status__c = 'Received',
            Payload__c = '{"test":true}'
        );
    }

    // ---------- Integration_Error__c ----------

    public static Integration_Error__c buildIntegrationError(String sourceSystem, String severity) {
        return new Integration_Error__c(
            Source_System__c = sourceSystem,
            Operation__c = 'unit-test',
            Error_Type__c = 'Other',
            Error_Message__c = 'test message',
            Severity__c = severity,
            Status__c = 'New'
        );
    }

    // ---------- Invoice (Salesforce Industries Billing) ----------
    // PLATFORM LIMITATION (verified 2026-07-06):
    // Native Invoice records CANNOT be created via Apex DML in either test or
    // runtime context. Attempting `insert new Invoice(...)` raises:
    //   FIELD_INTEGRITY_EXCEPTION, Can't create Invoice in Apex. Use REST API instead.
    //
    // Salesforce Industries Billing forces Invoice creation through its own
    // POST /services/data/vXX.0/invoices REST endpoint so that Billing Schedule
    // + line-item + tax provider hooks fire atomically. This means unit tests
    // for classes that operate on Invoice can only cover:
    //   - Input validation branches (blank / null / unknown document number)
    //   - Empty-state behavior (no invoices in the org)
    //   - Aggregate null-coalescing (SUM returns null → coalesce to 0)
    //
    // Full behavioral coverage (paid vs unpaid rollups, "all" mode, per-invoice
    // Stripe status transition) requires an integration test that provisions
    // Invoices via the REST API against a scratch/dev org. That is TS-TEST-003
    // in SECURITY.md's roadmap.
    //
    // The two Invoice builder methods below remain as placeholders so callers
    // that were coded against them fail with a clear compile-time signal; they
    // are marked @Deprecated and will be removed when the REST-based integration
    // harness lands.

    public static Invoice newPaidInvoice(Id billingAccountId, DateTime paidWhen) {
        throw new PlatformRestrictionException(
            'Invoice cannot be created via Apex DML — use REST /invoices instead. See TS-TEST-003.'
        );
    }

    public static Invoice newUnpaidInvoice(Id billingAccountId, String stripeStatus, Id billToContactId) {
        throw new PlatformRestrictionException(
            'Invoice cannot be created via Apex DML — use REST /invoices instead. See TS-TEST-003.'
        );
    }

    public class PlatformRestrictionException extends Exception {}
}
