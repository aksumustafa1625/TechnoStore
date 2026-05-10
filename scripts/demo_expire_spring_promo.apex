// DEMO TOGGLE: expire/restore Spring 2026 promo window in one Apex run.
//
// Switch the EXPIRE_NOW flag below:
//   true  -> EffectiveToDate = yesterday   -> products vanish from catalog after sync
//   false -> EffectiveToDate = 2026-12-31  -> products visible (within window)

final Boolean EXPIRE_NOW = true;     // <<< change to false to restore

Set<String> promoCodes = new Set<String>{'BUNDLE-GAMING-001','GAM-VR-001','AV-MON-004'};
Date newToDate = EXPIRE_NOW ? Date.today().addDays(-1) : Date.newInstance(2026, 12, 31);

List<ProductQualification> pqs = [SELECT Id, Product.Name FROM ProductQualification WHERE Product.ProductCode IN :promoCodes];
for (ProductQualification pq : pqs) pq.EffectiveToDate = newToDate;
update pqs;

System.debug('Mode: ' + (EXPIRE_NOW ? 'EXPIRED' : 'ACTIVE') + ' | New EffectiveToDate=' + newToDate);
for (ProductQualification pq : [SELECT Product.Name, EffectiveFromDate, EffectiveToDate FROM ProductQualification WHERE Product.ProductCode IN :promoCodes ORDER BY Product.Name]) {
    System.debug('  ' + pq.Product.Name + ' | ' + pq.EffectiveFromDate + ' .. ' + pq.EffectiveToDate);
}
