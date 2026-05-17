// Update all 6 demo Contacts to "Mustafa Aksu" with demo-user@example.com
// for the demo video — Contact identifies the video creator.
// Also propagate to Quote Billing/Shipping/QuoteTo Name fields.

System.debug('===== CONTACT UPDATE START =====');

TriggerHandler.bypass('OrderItemTriggerHandler');
TriggerHandler.bypass('QuoteLineItemTriggerHandler');
TriggerHandler.bypass('DocumentRecipientTriggerHandler');

List<String> demoCities = new List<String>{
    'Hamburg', 'München', 'Frankfurt am Main', 'Köln', 'Stuttgart', 'Wien'
};

// ============================================================
// Step 1: Update 6 Contacts to Mustafa Aksu
// ============================================================
List<Contact> contacts = [
    SELECT Id, FirstName, LastName, Email, Title, Account.Name
    FROM Contact
    WHERE Account.BillingCity IN :demoCities
];

for (Contact c : contacts) {
    c.FirstName = 'Mustafa';
    c.LastName  = 'Aksu';
    c.Email     = 'demo-user@example.com';
    // Title stays — that's role-specific per account
}
update contacts;

System.debug('Updated ' + contacts.size() + ' Contacts:');
for (Contact c : contacts) {
    System.debug('  ' + c.Account.Name + ' → ' + c.FirstName + ' ' + c.LastName + ' <' + c.Email + '> (' + c.Title + ')');
}

// ============================================================
// Step 2: Update 6 Quotes — Billing/Shipping/QuoteTo Names
// ============================================================
List<Quote> quotes = [
    SELECT Id, Name, BillingName, ShippingName, QuoteToName
    FROM Quote
    WHERE Account.BillingCity IN :demoCities
];

for (Quote q : quotes) {
    q.BillingName  = 'Mustafa Aksu';
    q.ShippingName = 'Mustafa Aksu';
    q.QuoteToName  = 'Mustafa Aksu';
}
update quotes;

System.debug('Updated ' + quotes.size() + ' Quotes — Names propagated to Mustafa Aksu');

TriggerHandler.clearBypass('OrderItemTriggerHandler');
TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
TriggerHandler.clearBypass('DocumentRecipientTriggerHandler');

// ============================================================
// Verification
// ============================================================
System.debug('===== VERIFICATION =====');
for (Contact c : [
    SELECT Account.Name, Account.BillingCity, FirstName, LastName, Email, Title
    FROM Contact
    WHERE Account.BillingCity IN :demoCities
    ORDER BY Account.BillingCity
]) {
    System.debug('  ' + c.Account.BillingCity + ' | ' + c.Account.Name + ' | ' + c.FirstName + ' ' + c.LastName + ' <' + c.Email + '> | ' + c.Title);
}

System.debug('===== UPDATE COMPLETE =====');
