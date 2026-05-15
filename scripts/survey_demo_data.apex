// Survey current demo data before destructive cleanup.
// Just READ — no DML in this script.

System.debug('===== CURRENT DEMO DATA STATE =====');

List<Account> accounts = [SELECT Id, Name, BillingCity, BillingCountry FROM Account ORDER BY CreatedDate];
System.debug('Accounts (' + accounts.size() + '):');
for (Account a : accounts) {
    System.debug('  - ' + a.Name + ' [' + a.BillingCity + ', ' + a.BillingCountry + ']');
}

List<Opportunity> opps = [SELECT Id, Name, AccountId, Account.Name, StageName FROM Opportunity ORDER BY CreatedDate];
System.debug('Opportunities (' + opps.size() + '):');
for (Opportunity o : opps) {
    System.debug('  - ' + o.Name + ' [Account: ' + o.Account.Name + ', Stage: ' + o.StageName + ']');
}

List<Quote> quotes = [SELECT Id, Name, OpportunityId, Opportunity.Name, Status FROM Quote ORDER BY CreatedDate];
System.debug('Quotes (' + quotes.size() + '):');
for (Quote q : quotes) {
    System.debug('  - ' + q.Name + ' [Opp: ' + q.Opportunity.Name + ', Status: ' + q.Status + ']');
}

Integer orderCount = [SELECT count() FROM Order];
Integer contractCount = [SELECT count() FROM Contract];
Integer assetCount = [SELECT count() FROM Asset];
Integer qliCount = [SELECT count() FROM QuoteLineItem];
Integer oliCount = [SELECT count() FROM OrderItem];

System.debug('Orders: ' + orderCount);
System.debug('Contracts: ' + contractCount);
System.debug('Assets: ' + assetCount);
System.debug('QuoteLineItems: ' + qliCount);
System.debug('OrderItems: ' + oliCount);

System.debug('===== SURVEY COMPLETE =====');
