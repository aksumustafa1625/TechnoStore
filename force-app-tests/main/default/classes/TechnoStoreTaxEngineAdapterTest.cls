/**
 * Unit tests for TechnoStoreTaxEngineAdapter — the commercetax.TaxEngineAdapter
 * implementation that applies flat 19% German VAT to every taxable line.
 *
 * SCOPE NOTE (Faz 1):
 * ==================
 * The commercetax namespace types this adapter depends on
 *   - commercetax.TaxTransactionRequest (abstract)
 *   - commercetax.TaxLineItemRequest (private constructor)
 *   - commercetax.TaxEngineContext (private constructor)
 * cannot be instantiated from Apex tests. Salesforce exposes the Tax Engine
 * SPI as a runtime contract invoked BY the platform's pricing/tax engine,
 * not as a client API. That means unit coverage of the calculation math
 * (100 EUR × 0.19 = 19 EUR tax) requires either (a) reflection into the
 * managed namespace, or (b) an end-to-end integration test that runs an
 * Invoice through the RLM Pricing Procedure, which in turn calls this adapter.
 *
 * What THIS test proves:
 *   - The adapter class compiles and can be instantiated
 *   - It correctly implements the commercetax.TaxEngineAdapter interface
 *     (would fail to compile otherwise)
 *
 * TS-TEST-002 (deferred): drive the adapter through the RLM Pricing procedure
 * with a real InvoiceLine graph and assert that Invoice.SAP_Tax_Amount__c
 * or the tax-line side effect equals amount × 0.19.
 */
@IsTest
private class TechnoStoreTaxEngineAdapterTest {

    @IsTest
    static void adapter_canBeInstantiated() {
        // The adapter's declaration `implements commercetax.TaxEngineAdapter` is
        // enforced by the Apex compiler — if the class ever drifts from the SPI
        // it will fail to deploy, which is a stronger guarantee than a runtime
        // instanceof check. Here we prove the class is instantiable at runtime,
        // giving us baseline coverage until the deferred integration test lands.
        Test.startTest();
        TechnoStoreTaxEngineAdapter adapter = new TechnoStoreTaxEngineAdapter();
        Test.stopTest();

        System.assertNotEquals(null, adapter, 'Adapter must be constructible');
    }
}
