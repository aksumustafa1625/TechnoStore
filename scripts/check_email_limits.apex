Map<String, System.OrgLimit> limits = OrgLimits.getMap();
System.OrgLimit single = limits.get('SingleEmail');
System.OrgLimit mass = limits.get('MassEmail');
if (single != null) System.debug('SingleEmail: used=' + single.getValue() + ' limit=' + single.getLimit() + ' remaining=' + (single.getLimit() - single.getValue()));
if (mass != null) System.debug('MassEmail: used=' + mass.getValue() + ' limit=' + mass.getLimit() + ' remaining=' + (mass.getLimit() - mass.getValue()));

List<OrgWideEmailAddress> owes = [SELECT Id, Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress];
for (OrgWideEmailAddress o : owes) System.debug('OWE: ' + o.Address + ' / ' + o.DisplayName);
