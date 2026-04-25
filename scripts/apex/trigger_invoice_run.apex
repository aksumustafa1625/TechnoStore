// Try different ConnectApi.Billing method patterns - probe for which exists
// Each call is wrapped to extract compile error messages

// Probe 1
try {
    ConnectApi.CreateInvoiceFromBillingSchedulesInputRepresentation inp = new ConnectApi.CreateInvoiceFromBillingSchedulesInputRepresentation();
    System.debug('CreateInvoiceFromBillingSchedulesInputRepresentation EXISTS');
} catch (Exception e) { System.debug('Probe1: ' + e.getMessage()); }
