// Bind 4 demo quotes to TechStore Entity (Legal Entity), so Tax Engine routes to TechStore VAT 19 Treatment
List<Quote> quotes = [
    SELECT Id, Name, LegalEntityId
    FROM Quote
    WHERE Id IN ('0Q0aj000002IHajCAG','0Q0aj000002IHakCAG','0Q0aj000002IHalCAG','0Q0aj000002IHamCAG')
];
for (Quote q : quotes) q.LegalEntityId = '0fwaj0000006IqHAAU'; // TechStore Entity
update quotes;
for (Quote q : quotes) System.debug('Bound: ' + q.Name + ' -> LegalEntity ' + q.LegalEntityId);
