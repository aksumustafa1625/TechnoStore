// Estimate the storage impact of deleting 72 candidate products
// (counts dependent records that would also be deleted: PBE, PCP, PSMO, PQ, PDQ).

Set<String> codesToDelete = new Set<String>{
    // A. Junk
    'EASY797987','FFCI987897A','PGJK89','PUP001A45','VIL8899089','REA0001','DCB09878907890',
    // B. Generic placeholders (codes)
    'CC','CS001','CLOUD001Pack','SVC-INS-002','DS001','KB001','LP001','LA001','LB001','LCP001','MO001','P001','PB001','PP001','SDP001','SP001','TB001','W001',
    // C. Certifications / Training
    'AC001','AT001','AST001','APT001','T001','DC001','LLM001','PC001','TPP01',
    // D. Abstract subscriptions
    'DEF001','ECOM01','QBO0021','LCD001','UA001','GPTW001',
    // NEW: Antivirus extras (Norton kept)
    'AV001','SW-AV-002','SW-AV-003',
    // NEW: Networking
    'NET-SW-002','NET-SEC-003','NET-RT-003','NET-RT-002','NET-SEC-001','NET-RT-001','BUNDLE-NETWORK-001','NET-SEC-002','NET-SW-001',
    // NEW: NAS
    'PER-STR-002','PER-STR-004',
    // NEW: Office software extras (Microsoft 365 Personal kept)
    'SW-OFF-002','GW001','SW-OFF-003','SW-CRE-001','SW-CRE-002',
    // CloudVault duplicates (50GB kept)
    'SW-CLD-002','SW-CLD-003'
};

// Also handle name-only matches for products without ProductCode
Set<String> namesToDelete = new Set<String>{
    'Activation Service','Billing Service','Installation Service','Planning Service','Shipping Service',
    'Specialized Certifications','Sun Thermal Compound','Zion Thermal Compound','Kyocera Thermal Compound Premium',
    'PowerSwerve R750 Rack Server'
};

List<Product2> targets = [
    SELECT Id, Name, ProductCode FROM Product2
    WHERE (ProductCode IN :codesToDelete OR (ProductCode = null AND Name IN :namesToDelete))
];
System.debug('Target products: ' + targets.size());

Set<Id> targetIds = new Set<Id>();
for (Product2 p : targets) targetIds.add(p.Id);

Integer pbeCount = [SELECT COUNT() FROM PricebookEntry WHERE Product2Id IN :targetIds];
Integer pcpCount = [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId IN :targetIds];
Integer psmoCount = [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id IN :targetIds];
Integer pqCount = [SELECT COUNT() FROM ProductQualification WHERE ProductId IN :targetIds];
Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId IN :targetIds];

System.debug('======== Records to be deleted ========');
System.debug('  Product2:                    ' + targets.size());
System.debug('  PricebookEntry:              ' + pbeCount);
System.debug('  ProductCategoryProduct:      ' + pcpCount);
System.debug('  ProductSellingModelOption:   ' + psmoCount);
System.debug('  ProductQualification:        ' + pqCount);
System.debug('  ProductDisqualification:     ' + pdqCount);
Integer total = targets.size() + pbeCount + pcpCount + psmoCount + pqCount + pdqCount;
System.debug('  TOTAL:                       ' + total);
System.debug('  ~Storage impact: ' + (total * 2) + ' KB (rough: 2KB/record avg)');
