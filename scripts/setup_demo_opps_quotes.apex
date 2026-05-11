// 1) Delete all Assets on the 4 demo accounts
// 2) Create / upsert 1 Opportunity per account
// 3) Create 1 Quote per Opportunity with full header fields

Set<String> demoAccountNames = new Set<String>{
    'Hamburg DataWorks AG',
    'München Industrial Systems GmbH',
    'Frankfurt FinTech Hub GmbH',
    'Köln Retail Cloud GmbH'
};

Map<String, Id> accountIdByName = new Map<String, Id>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :demoAccountNames]) {
    accountIdByName.put(a.Name, a.Id);
}
System.debug('Demo accounts found: ' + accountIdByName.size());

// ---- Step 1: Delete assets ----
Set<Id> acctIds = new Set<Id>(accountIdByName.values());
List<Asset> assets = [SELECT Id, Name, AccountId FROM Asset WHERE AccountId IN :acctIds];
System.debug('Assets to delete: ' + assets.size());
if (!assets.isEmpty()) {
    Database.delete(assets, false);
    // Empty recycle bin
    List<Asset> deletedAssets = [SELECT Id FROM Asset WHERE IsDeleted = true AND AccountId IN :acctIds LIMIT 200 ALL ROWS];
    if (!deletedAssets.isEmpty()) {
        try { Database.emptyRecycleBin(deletedAssets); } catch (Exception e) {}
    }
}

// ---- Step 2: Create/upsert Opportunities ----
// Same-named Opportunity per account
Map<String, String> oppNamesByAccount = new Map<String, String>{
    'Hamburg DataWorks AG'             => 'Hamburg DataWorks - Data Analytics Workstation Refresh Q2',
    'München Industrial Systems GmbH'  => 'München Industrial - IoT Pilot + Factory Floor Rollout 2026',
    'Frankfurt FinTech Hub GmbH'       => 'Frankfurt FinTech - Trading Desk Hardware Upgrade Q2',
    'Köln Retail Cloud GmbH'           => 'Köln Retail Cloud - Store Operations Hardware Refresh'
};

Map<String, Id> oppIdByAccount = new Map<String, Id>();
List<Opportunity> oppsToUpsert = new List<Opportunity>();

for (String acctName : accountIdByName.keySet()) {
    String oppName = oppNamesByAccount.get(acctName);
    List<Opportunity> existing = [SELECT Id FROM Opportunity WHERE Name = :oppName AND AccountId = :accountIdByName.get(acctName) LIMIT 1];
    Opportunity opp;
    if (existing.isEmpty()) {
        opp = new Opportunity(
            Name = oppName,
            AccountId = accountIdByName.get(acctName),
            StageName = 'Proposal/Price Quote',
            CloseDate = Date.today().addDays(30),
            Amount = 0,
            LeadSource = 'Web',
            Type = 'New Customer',
            Description = 'Hardware refresh / upgrade for Q2 2026 — workstation tier appropriate to ' + acctName + ' (Industries CPQ qualification engine will filter the catalog).'
        );
    } else {
        opp = existing[0];
        opp.StageName = 'Proposal/Price Quote';
        opp.CloseDate = Date.today().addDays(30);
    }
    oppsToUpsert.add(opp);
}
upsert oppsToUpsert;
for (Opportunity o : oppsToUpsert) oppIdByAccount.put([SELECT AccountId FROM Opportunity WHERE Id = :o.Id LIMIT 1].AccountId, o.Id);
// Simpler: rebuild map from Opps
oppIdByAccount.clear();
for (Opportunity o : [SELECT Id, AccountId, Name FROM Opportunity WHERE Id IN :oppsToUpsert]) {
    for (String acctName : accountIdByName.keySet()) {
        if (accountIdByName.get(acctName) == o.AccountId && o.Name == oppNamesByAccount.get(acctName)) {
            oppIdByAccount.put(acctName, o.Id);
        }
    }
}
System.debug('Opportunities ready: ' + oppIdByAccount.size());

// ---- Step 3: Create Quotes ----
Id standardPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

List<Quote> quotesToInsert = new List<Quote>();
Map<String, String> quoteDescriptions = new Map<String, String>{
    'Hamburg DataWorks AG'             => 'High-end data analytics workstation refresh for engineering team. Premium tier (Tech industry, 320 employees → all premium workstations qualify in Browse Catalog).',
    'München Industrial Systems GmbH'  => 'IoT pilot + factory floor hardware bundle. Mid-to-premium tier (Manufacturing industry, 580 employees → wide qualification range).',
    'Frankfurt FinTech Hub GmbH'       => 'Trading desk hardware upgrade with premium specs. Finance industry, 410 employees → premium tier qualifies.',
    'Köln Retail Cloud GmbH'           => 'Store operations hardware refresh — entry/SMB tier (Retail industry, 180 employees → only WorkStation X Pro + Office Workstation Plus + Business Workstation qualify; premium tier hidden by employee gate).'
};

for (String acctName : accountIdByName.keySet()) {
    Id oppId = oppIdByAccount.get(acctName);
    if (oppId == null) {
        System.debug('SKIP — no opp for ' + acctName);
        continue;
    }
    String quoteName = oppNamesByAccount.get(acctName);
    Quote q = new Quote(
        Name = quoteName,
        OpportunityId = oppId,
        Pricebook2Id = standardPb,
        Status = 'Draft',
        ExpirationDate = Date.today().addDays(30),
        Description = quoteDescriptions.get(acctName),
        BillingName = acctName,
        ShippingName = acctName
    );
    quotesToInsert.add(q);
}
insert quotesToInsert;
System.debug('Quotes created: ' + quotesToInsert.size());
for (Quote q : quotesToInsert) System.debug('  ' + q.Id + ' | ' + q.Name);
