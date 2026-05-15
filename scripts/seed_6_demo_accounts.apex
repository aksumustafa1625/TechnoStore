// Seed 6 new DACH-market demo accounts with their primary contacts,
// opportunities, and empty quotes. NO products / QuoteLineItems —
// user adds them in the UI after this script runs.
//
// Naming pattern intentionally different from prior demo round
// (river / region names instead of city descriptors).
//
// City mix: 4 Germany + 1 Austria + 1 Switzerland representation
// could be added later; currently 5 Germany + 1 Austria.

System.debug('===== SEED START =====');

// Disable trigger side effects during inserts
TriggerHandler.bypass('OrderItemTriggerHandler');
TriggerHandler.bypass('QuoteLineItemTriggerHandler');
TriggerHandler.bypass('DocumentRecipientTriggerHandler');

// Standard pricebook (required for Quote)
Id standardPricebookId;
try {
    standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
} catch (Exception e) {
    // No standard pricebook? Try the test version
    standardPricebookId = Test.getStandardPricebookId();
}

// ============================================================
// Step 1: Create 6 Accounts
// ============================================================
List<Account> accounts = new List<Account>{
    new Account(
        Name = 'Elbe Technology Distribution GmbH',
        BillingStreet = 'Reeperbahn 142',
        BillingCity = 'Hamburg',
        BillingPostalCode = '20359',
        BillingCountry = 'Germany',
        Phone = '+49 40 555 0142',
        NumberOfEmployees = 85,
        Industry = 'Technology',
        Type = 'Customer - Channel',
        Description = 'B2B IT distributor serving Hamburg-region resellers'
    ),
    new Account(
        Name = 'Isar Workplace Solutions AG',
        BillingStreet = 'Maximilianstraße 28',
        BillingCity = 'München',
        BillingPostalCode = '80539',
        BillingCountry = 'Germany',
        Phone = '+49 89 555 0228',
        NumberOfEmployees = 240,
        Industry = 'Manufacturing',
        Type = 'Customer - Direct',
        Description = 'Workplace equipment supplier for Munich Mittelstand'
    ),
    new Account(
        Name = 'Main Capital IT-Partners GmbH',
        BillingStreet = 'Mainzer Landstraße 47',
        BillingCity = 'Frankfurt am Main',
        BillingPostalCode = '60329',
        BillingCountry = 'Germany',
        Phone = '+49 69 555 0347',
        NumberOfEmployees = 120,
        Industry = 'Finance',
        Type = 'Customer - Direct',
        Description = 'IT hardware partner for financial-services firms'
    ),
    new Account(
        Name = 'Rheinland Office Vertrieb GmbH',
        BillingStreet = 'Hohe Straße 89',
        BillingCity = 'Köln',
        BillingPostalCode = '50667',
        BillingCountry = 'Germany',
        Phone = '+49 221 555 0489',
        NumberOfEmployees = 55,
        Industry = 'Retail',
        Type = 'Customer - Channel',
        Description = 'Office equipment reseller for Rhineland businesses'
    ),
    new Account(
        Name = 'Schwaben Engineering Systems GmbH',
        BillingStreet = 'Königstraße 156',
        BillingCity = 'Stuttgart',
        BillingPostalCode = '70173',
        BillingCountry = 'Germany',
        Phone = '+49 711 555 0556',
        NumberOfEmployees = 180,
        Industry = 'Engineering',
        Type = 'Customer - Direct',
        Description = 'Engineering workstation supplier for Baden-Württemberg'
    ),
    new Account(
        Name = 'Donau Business Hardware GmbH',
        BillingStreet = 'Mariahilfer Straße 73',
        BillingCity = 'Wien',
        BillingPostalCode = '1060',
        BillingCountry = 'Austria',
        Phone = '+43 1 555 0673',
        NumberOfEmployees = 95,
        Industry = 'Consulting',
        Type = 'Customer - Channel',
        Description = 'Austrian business hardware distributor'
    )
};

insert accounts;
System.debug('Inserted ' + accounts.size() + ' Accounts');
for (Account a : accounts) System.debug('  ✓ ' + a.Name + ' [' + a.BillingCity + ']');

// ============================================================
// Step 2: Create 1 Primary Contact per Account
// ============================================================
List<Contact> contacts = new List<Contact>{
    new Contact(AccountId = accounts[0].Id, FirstName = 'Klaus',   LastName = 'Hoffmann',  Email = 'klaus.hoffmann@elbe-tech.example',         Phone = '+49 40 555 0143',  Title = 'IT Procurement Manager'),
    new Contact(AccountId = accounts[1].Id, FirstName = 'Andrea',  LastName = 'Müller',    Email = 'andrea.mueller@isar-workplace.example',    Phone = '+49 89 555 0229',  Title = 'Head of Operations'),
    new Contact(AccountId = accounts[2].Id, FirstName = 'Stefan',  LastName = 'Becker',    Email = 'stefan.becker@main-capital-it.example',    Phone = '+49 69 555 0348',  Title = 'Senior IT Buyer'),
    new Contact(AccountId = accounts[3].Id, FirstName = 'Sandra',  LastName = 'Schmidt',   Email = 'sandra.schmidt@rheinland-office.example',  Phone = '+49 221 555 0490', Title = 'Office Manager'),
    new Contact(AccountId = accounts[4].Id, FirstName = 'Markus',  LastName = 'Wagner',    Email = 'markus.wagner@schwaben-eng.example',       Phone = '+49 711 555 0557', Title = 'Engineering Director'),
    new Contact(AccountId = accounts[5].Id, FirstName = 'Lisa',    LastName = 'Hofbauer',  Email = 'lisa.hofbauer@donau-hw.example',           Phone = '+43 1 555 0674',   Title = 'Procurement Lead')
};

insert contacts;
System.debug('Inserted ' + contacts.size() + ' Contacts');

// ============================================================
// Step 3: Create 1 Opportunity per Account
// ============================================================
List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(AccountId = accounts[0].Id, Name = '2026 Workstation Refresh Program',     StageName = 'Qualification',  CloseDate = Date.today().addDays(45), Description = 'Annual workstation refresh for the Hamburg distribution team'),
    new Opportunity(AccountId = accounts[1].Id, Name = 'Annual Hardware Procurement Cycle',    StageName = 'Needs Analysis', CloseDate = Date.today().addDays(60), Description = 'Multi-site hardware procurement for Munich manufacturing operations'),
    new Opportunity(AccountId = accounts[2].Id, Name = 'Office Modernization Initiative',     StageName = 'Qualification',  CloseDate = Date.today().addDays(30), Description = 'Frankfurt finance-floor modernization with high-end workstations'),
    new Opportunity(AccountId = accounts[3].Id, Name = 'Branch Office Rollout Phase 1',       StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(20), Description = 'First wave of Rhineland branch office equipment rollout'),
    new Opportunity(AccountId = accounts[4].Id, Name = 'Engineering Workstation Upgrade',     StageName = 'Needs Analysis', CloseDate = Date.today().addDays(50), Description = 'CAD-grade workstation upgrade for Stuttgart engineering team'),
    new Opportunity(AccountId = accounts[5].Id, Name = 'Regional Office Equipment Order',     StageName = 'Qualification',  CloseDate = Date.today().addDays(40), Description = 'Vienna headquarters hardware refresh order')
};

insert opps;
System.debug('Inserted ' + opps.size() + ' Opportunities');

// ============================================================
// Step 4: Create 1 Empty Quote per Opportunity (no Line Items)
// ============================================================
List<Quote> quotes = new List<Quote>();
String[] quoteSuffixes = new String[]{
    'Elbe',
    'Isar',
    'Main',
    'Rheinland',
    'Schwaben',
    'Donau'
};

for (Integer i = 0; i < opps.size(); i++) {
    Quote q = new Quote(
        OpportunityId  = opps[i].Id,
        Pricebook2Id   = standardPricebookId,
        ContactId      = contacts[i].Id,
        Name           = 'Quote — ' + quoteSuffixes[i] + ' — Q1-2026',
        ExpirationDate = Date.today().addDays(30),
        Status         = 'Draft',
        BillingStreet     = accounts[i].BillingStreet,
        BillingCity       = accounts[i].BillingCity,
        BillingPostalCode = accounts[i].BillingPostalCode,
        BillingCountry    = accounts[i].BillingCountry,
        ShippingStreet     = accounts[i].BillingStreet,
        ShippingCity       = accounts[i].BillingCity,
        ShippingPostalCode = accounts[i].BillingPostalCode,
        ShippingCountry    = accounts[i].BillingCountry,
        Description    = 'Quote awaiting product line items — add via Browse Catalog'
    );
    quotes.add(q);
}

insert quotes;
System.debug('Inserted ' + quotes.size() + ' Quotes (empty — no line items)');

// ============================================================
// Re-enable triggers
// ============================================================
TriggerHandler.clearBypass('OrderItemTriggerHandler');
TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
TriggerHandler.clearBypass('DocumentRecipientTriggerHandler');

// ============================================================
// Final summary
// ============================================================
System.debug('===== SEED COMPLETE — RECORDS CREATED =====');
List<Quote> finalQuotes = [
    SELECT Id, Name, Opportunity.Name, Opportunity.Account.Name, Opportunity.Account.BillingCity,
           Status, Contact.Name
    FROM Quote
    WHERE Id IN :quotes
    ORDER BY Opportunity.Account.Name
];
for (Quote q : finalQuotes) {
    System.debug('  ✓ ' + q.Opportunity.Account.Name +
                 ' [' + q.Opportunity.Account.BillingCity + ']' +
                 ' → ' + q.Opportunity.Name +
                 ' → ' + q.Name +
                 ' (Contact: ' + q.Contact.Name + ')');
}

System.debug('');
System.debug('Next steps for the user:');
System.debug('  1. Open Salesforce → App Launcher → TechnoStore Sales');
System.debug('  2. Open each Quote in turn');
System.debug('  3. Click Browse Catalog → add Bundle / single products as needed');
System.debug('  4. Configure bundles, then proceed to Order → Contract → Payment');
