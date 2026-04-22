AttributeDefinition storAttr = [SELECT Id FROM AttributeDefinition WHERE Name = 'Storage' LIMIT 1];
AttributeDefinition gfxAttr = [SELECT Id FROM AttributeDefinition WHERE Name = 'Graphics' LIMIT 1];
ProductClassification lapClass = [SELECT Id FROM ProductClassification WHERE Name = 'Laptop' LIMIT 1];
List<Product2> lapProds = [SELECT Id, Name FROM Product2 WHERE BasedOnId = :lapClass.Id AND IsActive = true];

PriceAdjustmentSchedule storSched = [SELECT Id FROM PriceAdjustmentSchedule WHERE Name = 'Storage Upgrade Pricing' LIMIT 1];
PriceAdjustmentSchedule gfxSched = [SELECT Id FROM PriceAdjustmentSchedule WHERE Name = 'Graphics Upgrade Pricing' LIMIT 1];
DateTime eff = DateTime.newInstance(2026,1,1,12,0,0);

Map<String, Product2> prodByPrefix = new Map<String, Product2>();
for(Product2 p : lapProds) {
    prodByPrefix.put(p.Name.left(12).replaceAll('[^a-zA-Z0-9]', ''), p);
}

List<AttributeBasedAdjustment> adjs = new List<AttributeBasedAdjustment>();
for(AttributeBasedAdjRule r : [SELECT Id, Name FROM AttributeBasedAdjRule 
    WHERE Name LIKE '%-SSD512' OR Name LIKE '%-SSD1TB' OR Name LIKE '%-SSD2TB' OR Name LIKE '%-RTX']) {
    String prefix = r.Name.substringBeforeLast('-');
    Product2 p = prodByPrefix.get(prefix);
    if(p == null) continue;
    if(r.Name.endsWith('-SSD512'))
        adjs.add(new AttributeBasedAdjustment(ProductId=p.Id, AttributeBasedAdjRuleId=r.Id, PriceAdjustmentScheduleId=storSched.Id, AdjustmentType='Amount', AdjustmentValue=50, EffectiveFrom=eff));
    else if(r.Name.endsWith('-SSD1TB'))
        adjs.add(new AttributeBasedAdjustment(ProductId=p.Id, AttributeBasedAdjRuleId=r.Id, PriceAdjustmentScheduleId=storSched.Id, AdjustmentType='Amount', AdjustmentValue=100, EffectiveFrom=eff));
    else if(r.Name.endsWith('-SSD2TB'))
        adjs.add(new AttributeBasedAdjustment(ProductId=p.Id, AttributeBasedAdjRuleId=r.Id, PriceAdjustmentScheduleId=storSched.Id, AdjustmentType='Amount', AdjustmentValue=150, EffectiveFrom=eff));
    else if(r.Name.endsWith('-RTX'))
        adjs.add(new AttributeBasedAdjustment(ProductId=p.Id, AttributeBasedAdjRuleId=r.Id, PriceAdjustmentScheduleId=gfxSched.Id, AdjustmentType='Amount', AdjustmentValue=300, EffectiveFrom=eff));
}

Database.SaveResult[] ar = Database.insert(adjs, false);
Integer s = 0;
for(Database.SaveResult r : ar) { if(r.isSuccess()) s++; else System.debug('❌ ' + r.getErrors()[0].getMessage()); }
System.debug('✅ Adjustments: ' + s + '/' + adjs.size());