// Update all 3 TaxRates to reference TechStore Entity LE (match new TaxTreatment)
List<TaxRate> rates = [SELECT Id, TaxCode, LegalEntityId FROM TaxRate];
for (TaxRate r : rates) {
    r.LegalEntityId = '0fwaj0000006IqHAAU';
}
update rates;
System.debug('Updated ' + rates.size() + ' TaxRates to TechStore Entity LE');

// Verify
for (TaxRate r : [SELECT Id, TaxCode, Rate, LegalEntityId, GeoCountryId FROM TaxRate]) {
    System.debug('Rate: ' + r.TaxCode + ' | ' + r.Rate + '% | LE=' + r.LegalEntityId + ' | GeoCountry=' + r.GeoCountryId);
}
