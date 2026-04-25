// Path: change new TaxTreatment LE to avoid conflict, activate, make it default
TaxTreatment newTt = new TaxTreatment(Id='1ttaj000000BaxpAAC', LegalEntityId='0fwaj0000006IqHAAU');
try { update newTt; System.debug('New TT LE changed to TechStore Entity'); }
catch (Exception e) { System.debug('LE change fail: ' + e.getMessage()); }

TaxTreatment newTtActivate = new TaxTreatment(Id='1ttaj000000BaxpAAC', Status='Active');
try { update newTtActivate; System.debug('New TaxTreatment activated'); }
catch (Exception e) { System.debug('Activate fail: ' + e.getMessage()); }

TaxPolicy tp = new TaxPolicy(Id='1Tpaj000000IKTJCA4', DefaultTaxTreatmentId='1ttaj000000BaxpAAC');
try { update tp; System.debug('TaxPolicy default = new'); }
catch (Exception e) { System.debug('Set default fail: ' + e.getMessage()); }

TaxTreatment oldTt = new TaxTreatment(Id='1ttaj0000009UWjAAM', Status='Inactive');
try { update oldTt; System.debug('Old TaxTreatment inactivated'); }
catch (Exception e) { System.debug('Inactivate old fail: ' + e.getMessage()); }

TaxTreatment v = [SELECT Id, Name, Status, IsTaxable, TaxEngineId, TaxCode, LegalEntityId, TaxPolicyId FROM TaxTreatment WHERE Id='1ttaj000000BaxpAAC'];
System.debug('New TT: Status=' + v.Status + ' Tax=' + v.IsTaxable + ' Engine=' + v.TaxEngineId + ' Code=' + v.TaxCode + ' LE=' + v.LegalEntityId);
TaxPolicy p = [SELECT Id, Status, DefaultTaxTreatmentId FROM TaxPolicy WHERE Id='1Tpaj000000IKTJCA4'];
System.debug('Policy: Status=' + p.Status + ' Default=' + p.DefaultTaxTreatmentId);
