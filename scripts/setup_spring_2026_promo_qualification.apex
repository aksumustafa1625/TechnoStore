// Tech Spring Sale 2026 — date-based ProductQualification demo.
// Sets EffectiveFromDate=2026-05-01 and EffectiveToDate=2026-12-31 on three
// promotional products. Engine evaluates date range at runtime: products
// only appear in Browse Catalog while today falls within the window.
//
// Demo: today (2026-05-09) is in range -> products visible. Move
// EffectiveToDate to 2026-05-08 (yesterday) -> products vanish from catalog.
//
// After running, user must run all 4 UI refreshes:
//   1. Setup -> Product Qualification -> Refresh
//   2. Setup -> Product Disqualification -> Refresh
//   3. Setup -> Product Discovery Settings -> Rebuild Index
//   4. Setup -> Salesforce Pricing Setup -> Sync

Set<String> promoCodes = new Set<String>{'BUNDLE-GAMING-001','GAM-VR-001','AV-MON-004'};

List<ProductQualification> pqs = [SELECT Id, Product.Name, MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE Product.ProductCode IN :promoCodes];
System.debug('Found ' + pqs.size() + ' ProductQualification records on promo products');

for (ProductQualification pq : pqs) {
    pq.EffectiveFromDate = Date.newInstance(2026, 5, 1);
    pq.EffectiveToDate = Date.newInstance(2026, 12, 31);
    // Keep employees open (this is a date-based promo, not size-restricted)
    pq.MinNumberOfEmployees__c = 0;
    pq.MaxNumberOfEmployees__c = 999999;
}
update pqs;
System.debug('Updated to window: 2026-05-01 to 2026-12-31');

System.debug('======== Verification ========');
for (ProductQualification pq : [SELECT Product.Name, EffectiveFromDate, EffectiveToDate, MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE Product.ProductCode IN :promoCodes ORDER BY Product.Name]) {
    System.debug('  ' + pq.Product.Name.rightPad(28) + ' | Window: ' + pq.EffectiveFromDate + ' .. ' + pq.EffectiveToDate + ' | Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c);
}

Date today = Date.today();
Date startDate = Date.newInstance(2026, 5, 1);
Date endDate = Date.newInstance(2026, 12, 31);
Boolean inRange = (today >= startDate && today < endDate);
System.debug('Today=' + today + ' | Window 2026-05-01..2026-12-31 | In range? ' + inRange);
