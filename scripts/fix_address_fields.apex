// Fix address completeness on the 6 demo Accounts + their Quotes
// so Order activation has everything it needs:
//   - Account.Shipping* = Account.Billing* (same address for demo)
//   - Quote.Billing* / Shipping* / QuoteTo* fully populated incl. *Name
//   - Quote.ContactId verified
//
// Opportunity has no standard address fields — skipped intentionally.

System.debug('===== ADDRESS FIX START =====');

TriggerHandler.bypass('OrderItemTriggerHandler');
TriggerHandler.bypass('QuoteLineItemTriggerHandler');

// ============================================================
// Step 1: Update Account — copy Billing to Shipping for the 6 demo accounts
// ============================================================
List<String> demoCities = new List<String>{
    'Hamburg', 'München', 'Frankfurt am Main', 'Köln', 'Stuttgart', 'Wien'
};
List<Account> accounts = [
    SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
           ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
    FROM Account
    WHERE BillingCity IN :demoCities
];

for (Account a : accounts) {
    a.ShippingStreet     = a.BillingStreet;
    a.ShippingCity       = a.BillingCity;
    a.ShippingState      = a.BillingState;
    a.ShippingPostalCode = a.BillingPostalCode;
    a.ShippingCountry    = a.BillingCountry;
}
update accounts;
System.debug('Updated ' + accounts.size() + ' Accounts with Shipping = Billing');

// ============================================================
// Step 2: Update Quotes — populate Billing / Shipping / QuoteTo with Name fields
// ============================================================
List<Quote> quotes = [
    SELECT Id, Name, AccountId, ContactId,
           Account.Name, Account.BillingStreet, Account.BillingCity, Account.BillingState,
                       Account.BillingPostalCode, Account.BillingCountry,
           Contact.Name, Contact.FirstName, Contact.LastName,
           BillingStreet, ShippingStreet, QuoteToStreet, BillingName, ShippingName, QuoteToName
    FROM Quote
    WHERE Account.BillingCity IN :demoCities
];

for (Quote q : quotes) {
    String contactFullName = (q.Contact != null && q.Contact.Name != null) ? q.Contact.Name : q.Account.Name;

    // Billing block (who pays)
    q.BillingName       = contactFullName;
    q.BillingStreet     = q.Account.BillingStreet;
    q.BillingCity       = q.Account.BillingCity;
    q.BillingState      = q.Account.BillingState;
    q.BillingPostalCode = q.Account.BillingPostalCode;
    q.BillingCountry    = q.Account.BillingCountry;

    // Shipping block (where goods go — same as Billing for demo)
    q.ShippingName       = contactFullName;
    q.ShippingStreet     = q.Account.BillingStreet;
    q.ShippingCity       = q.Account.BillingCity;
    q.ShippingState      = q.Account.BillingState;
    q.ShippingPostalCode = q.Account.BillingPostalCode;
    q.ShippingCountry    = q.Account.BillingCountry;

    // QuoteTo block (quote recipient — typically same as Billing contact)
    q.QuoteToName       = contactFullName;
    q.QuoteToStreet     = q.Account.BillingStreet;
    q.QuoteToCity       = q.Account.BillingCity;
    q.QuoteToState      = q.Account.BillingState;
    q.QuoteToPostalCode = q.Account.BillingPostalCode;
    q.QuoteToCountry    = q.Account.BillingCountry;
}
update quotes;
System.debug('Updated ' + quotes.size() + ' Quotes with full address blocks (Billing + Shipping + QuoteTo + Names)');

TriggerHandler.clearBypass('OrderItemTriggerHandler');
TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');

// ============================================================
// Verification
// ============================================================
System.debug('===== VERIFICATION =====');
for (Quote q : [
    SELECT Name, BillingName, BillingCity, ShippingName, ShippingCity, QuoteToName, QuoteToCity, ContactId
    FROM Quote
    WHERE Account.BillingCity IN :demoCities
    ORDER BY Name
]) {
    System.debug('  ' + q.Name);
    System.debug('    BillTo:  ' + q.BillingName + ' @ ' + q.BillingCity);
    System.debug('    ShipTo:  ' + q.ShippingName + ' @ ' + q.ShippingCity);
    System.debug('    QuoteTo: ' + q.QuoteToName + ' @ ' + q.QuoteToCity);
    System.debug('    Contact: ' + (q.ContactId != null ? 'set' : 'NULL ⚠️'));
}

System.debug('===== ADDRESS FIX COMPLETE =====');
System.debug('Note: Opportunity has no native address fields. If your org has custom Opp address fields, they should be populated separately.');
