// Create 4 demo Quote headers (no line items - those will be added live via Browse Catalog)
// Each Quote linked to existing Account + Opportunity + Contact

Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

// Helper to find a record or return null
Map<String, Account> accountByKey = new Map<String, Account>();
for (Account a : [
    SELECT Id, Name, BillingStreet, BillingCity, BillingPostalCode, BillingCountry
    FROM Account
    WHERE Name LIKE '%Hamburg DataWorks%'
       OR Name LIKE '%nchen Industrial%'
       OR Name LIKE '%Munchen Industrial%'
       OR Name LIKE '%ln Retail Cloud%'
       OR Name LIKE '%Koln Retail Cloud%'
       OR Name LIKE '%Stuttgart Mobility Tech%'
]) {
    if (a.Name.contains('Hamburg DataWorks')) accountByKey.put('hamburg', a);
    else if (a.Name.toLowerCase().contains('nchen industrial') || a.Name.toLowerCase().contains('munchen industrial')) accountByKey.put('munchen', a);
    else if (a.Name.toLowerCase().contains('ln retail cloud') || a.Name.toLowerCase().contains('koln retail cloud')) accountByKey.put('koln', a);
    else if (a.Name.contains('Stuttgart Mobility Tech')) accountByKey.put('stuttgart', a);
}

System.debug('Accounts found: ' + accountByKey.keySet());
for (String k : accountByKey.keySet()) System.debug('  ' + k + ' -> ' + accountByKey.get(k).Id + ' (' + accountByKey.get(k).Name + ')');

// Find latest Opportunity per Account
Map<Id, Opportunity> oppByAccountId = new Map<Id, Opportunity>();
for (Opportunity o : [
    SELECT Id, Name, AccountId, Pricebook2Id
    FROM Opportunity
    WHERE AccountId IN :accountByKey.values()
    ORDER BY CreatedDate DESC
]) {
    if (!oppByAccountId.containsKey(o.AccountId)) {
        oppByAccountId.put(o.AccountId, o);
    }
}

// Find primary Contact per Account (most recent)
Map<Id, Contact> contactByAccountId = new Map<Id, Contact>();
for (Contact c : [
    SELECT Id, AccountId, Name, FirstName, LastName, Email, Phone
    FROM Contact
    WHERE AccountId IN :accountByKey.values()
    ORDER BY CreatedDate DESC
]) {
    if (!contactByAccountId.containsKey(c.AccountId)) {
        contactByAccountId.put(c.AccountId, c);
    }
}

// Build the 4 Quote payloads
List<Quote> quotesToInsert = new List<Quote>();

// 1. Hamburg DataWorks AG
if (accountByKey.containsKey('hamburg')) {
    Account a = accountByKey.get('hamburg');
    Opportunity opp = oppByAccountId.get(a.Id);
    Contact c = contactByAccountId.get(a.Id);
    if (opp != null) {
        quotesToInsert.add(new Quote(
            Name = 'Hamburg DataWorks - Data Analytics Workstation Refresh Q2',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.newInstance(2026, 6, 15),
            Description = 'Q2 workstation refresh for analyst and data engineering teams. Includes secure network infrastructure baseline (Network Security Kit) plus 8x developer towers, 4x analyst all-in-one units, and 3-year hardware coverage.',
            ContactId = (c != null ? c.Id : null),
            Email = (c != null && c.Email != null ? c.Email : 'demo-recipient@example.com'),
            Phone = (c != null && c.Phone != null ? c.Phone : '+49 40 9988 1100'),
            BillingName = a.Name,
            BillingStreet = 'Mönckebergstraße 27',
            BillingCity = 'Hamburg',
            BillingPostalCode = '20095',
            BillingCountry = 'Germany',
            ShippingName = a.Name,
            ShippingStreet = 'Mönckebergstraße 27',
            ShippingCity = 'Hamburg',
            ShippingPostalCode = '20095',
            ShippingCountry = 'Germany'
        ));
    }
}

// 2. München Industrial Systems GmbH
if (accountByKey.containsKey('munchen')) {
    Account a = accountByKey.get('munchen');
    Opportunity opp = oppByAccountId.get(a.Id);
    Contact c = contactByAccountId.get(a.Id);
    if (opp != null) {
        quotesToInsert.add(new Quote(
            Name = 'München Industrial - IoT Pilot + Factory Floor Rollout 2026',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.newInstance(2026, 7, 1),
            Description = 'Phase-1 IoT pilot deployment: 5x Smart Home Starter kits as IoT pilot cells, 15x rugged factory-floor tablets, 6x control-room workstations, facility-grade WiFi backbone, 3-year coverage on all tablets.',
            ContactId = (c != null ? c.Id : null),
            Email = (c != null && c.Email != null ? c.Email : 'demo-recipient@example.com'),
            Phone = (c != null && c.Phone != null ? c.Phone : '+49 89 4477 6655'),
            BillingName = a.Name,
            BillingStreet = 'Maximilianstraße 13',
            BillingCity = 'München',
            BillingPostalCode = '80539',
            BillingCountry = 'Germany',
            ShippingName = a.Name,
            ShippingStreet = 'Maximilianstraße 13',
            ShippingCity = 'München',
            ShippingPostalCode = '80539',
            ShippingCountry = 'Germany'
        ));
    }
}

// 3. Köln Retail Cloud GmbH
if (accountByKey.containsKey('koln')) {
    Account a = accountByKey.get('koln');
    Opportunity opp = oppByAccountId.get(a.Id);
    Contact c = contactByAccountId.get(a.Id);
    if (opp != null) {
        quotesToInsert.add(new Quote(
            Name = 'Köln Retail Cloud - Omnichannel POS Refresh',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.newInstance(2026, 6, 30),
            Description = 'In-store POS terminal modernization: 3x back-office Home Office Bundles for store managers, 4x AllInOne 27" Touch as customer-facing self-checkout / POS terminals, 6x TabPro 11" tablets for floor sales associates.',
            ContactId = (c != null ? c.Id : null),
            Email = (c != null && c.Email != null ? c.Email : 'demo-recipient@example.com'),
            Phone = (c != null && c.Phone != null ? c.Phone : '+49 221 8855 9966'),
            BillingName = a.Name,
            BillingStreet = 'Hohe Straße 88',
            BillingCity = 'Köln',
            BillingPostalCode = '50667',
            BillingCountry = 'Germany',
            ShippingName = a.Name,
            ShippingStreet = 'Hohe Straße 88',
            ShippingCity = 'Köln',
            ShippingPostalCode = '50667',
            ShippingCountry = 'Germany'
        ));
    }
}

// 4. Stuttgart Mobility Tech AG
if (accountByKey.containsKey('stuttgart')) {
    Account a = accountByKey.get('stuttgart');
    Opportunity opp = oppByAccountId.get(a.Id);
    Contact c = contactByAccountId.get(a.Id);
    if (opp != null) {
        quotesToInsert.add(new Quote(
            Name = 'Stuttgart Mobility - Connected Vehicle UX Lab Setup',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.newInstance(2026, 7, 10),
            Description = 'Connected-vehicle UX lab buildout for the OEM partner program: 4x Creator Studio Bundles for high-end CAD/3D rendering, 10x premium engineering laptops, 6x VisionXR headsets for in-vehicle HMI VR prototyping, 3x DrawPad Pro for UX/UI design team, 3-year hardware coverage.',
            ContactId = (c != null ? c.Id : null),
            Email = (c != null && c.Email != null ? c.Email : 'demo-recipient@example.com'),
            Phone = (c != null && c.Phone != null ? c.Phone : '+49 711 4422 8877'),
            BillingName = a.Name,
            BillingStreet = 'Königstraße 1A',
            BillingCity = 'Stuttgart',
            BillingPostalCode = '70173',
            BillingCountry = 'Germany',
            ShippingName = a.Name,
            ShippingStreet = 'Königstraße 1A',
            ShippingCity = 'Stuttgart',
            ShippingPostalCode = '70173',
            ShippingCountry = 'Germany'
        ));
    }
}

System.debug('Quotes to insert: ' + quotesToInsert.size());

if (!quotesToInsert.isEmpty()) {
    Database.SaveResult[] results = Database.insert(quotesToInsert, false);
    Integer i = 0;
    for (Database.SaveResult r : results) {
        if (r.isSuccess()) {
            System.debug('CREATED: ' + r.getId() + ' - ' + quotesToInsert[i].Name);
        } else {
            System.debug('FAILED: ' + quotesToInsert[i].Name + ' -> ' + r.getErrors()[0].getMessage());
        }
        i++;
    }
}
