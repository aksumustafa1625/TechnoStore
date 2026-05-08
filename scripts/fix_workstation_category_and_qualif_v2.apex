// Fix the Premium Workstation Pro setup so the demo actually filters in the UI:
//   1. Add the new product to the existing "Workstation" category (alongside other workstations)
//   2. Tighten RenderStation Ultra (USD 4899, premium) to Min=100 + 12 industry blocks
//   3. Leave WorkStation X Pro (USD 3299, entry) open so disqualified accounts still see SOMETHING

final Id PREMIUM_WS_ID    = '01taj00000Rv7WfAAJ';   // Premium Workstation Pro
final Id RENDER_ULTRA_ID  = '01taj00000QnnlbAAB';   // RenderStation Ultra
final Id WORKSTATION_CAT  = '0ZGaj000000LPRgGAO';   // Workstation category

// 1) Add Premium Workstation Pro to Workstation category
List<ProductCategoryProduct> existingPcp = [SELECT Id FROM ProductCategoryProduct WHERE ProductId = :PREMIUM_WS_ID AND ProductCategoryId = :WORKSTATION_CAT];
if (existingPcp.isEmpty()) {
    insert new ProductCategoryProduct(ProductId = PREMIUM_WS_ID, ProductCategoryId = WORKSTATION_CAT);
    System.debug('Linked Premium Workstation Pro to Workstation category');
} else {
    System.debug('Already linked to Workstation category');
}

// 2) Tighten RenderStation Ultra qualification (update existing PQ from Min=0 to Min=100)
ProductQualification renderPq = [SELECT Id, MinNumberOfEmployees__c FROM ProductQualification WHERE ProductId = :RENDER_ULTRA_ID LIMIT 1];
if (renderPq.MinNumberOfEmployees__c < 100) {
    renderPq.MinNumberOfEmployees__c = 100;
    update renderPq;
    System.debug('Updated RenderStation Ultra PQ: Min=100');
}

// 3) Add ProductDisqualifications to RenderStation Ultra
List<String> blockedIndustries = new List<String>{
    'Retail', 'Healthcare', 'Education', 'Hospitality', 'Recreation',
    'Not For Profit', 'Apparel', 'Food & Beverage', 'Government',
    'Construction', 'Agriculture', 'Entertainment'
};
Set<String> existingPdqIndustries = new Set<String>();
for (ProductDisqualification pdq : [SELECT Industry__c FROM ProductDisqualification WHERE ProductId = :RENDER_ULTRA_ID]) {
    existingPdqIndustries.add(pdq.Industry__c);
}
List<ProductDisqualification> newPdqs = new List<ProductDisqualification>();
for (String industry : blockedIndustries) {
    if (!existingPdqIndustries.contains(industry)) {
        newPdqs.add(new ProductDisqualification(
            ProductId = RENDER_ULTRA_ID,
            Industry__c = industry,
            Reason = 'RenderStation Ultra (Dual Xeon, 128GB ECC, NVIDIA A5000) is intended for technology, finance, manufacturing, and engineering enterprises. ' + industry + ' is outside the target customer profile.',
            EffectiveFromDate = Date.today().addDays(-1),
            EffectiveToDate = Date.newInstance(2099, 12, 31)
        ));
    }
}
if (!newPdqs.isEmpty()) {
    insert newPdqs;
    System.debug('Added ' + newPdqs.size() + ' Disqualifications to RenderStation Ultra');
}

System.debug('======== Final state — Workstation category contents ========');
for (ProductCategoryProduct pcp : [SELECT Product.Name, Product.ProductCode, ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :WORKSTATION_CAT]) {
    Integer pqCount = [SELECT COUNT() FROM ProductQualification WHERE ProductId = :pcp.ProductId];
    Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :pcp.ProductId];
    Decimal minEmp = pqCount > 0 ? [SELECT MinNumberOfEmployees__c FROM ProductQualification WHERE ProductId = :pcp.ProductId LIMIT 1].MinNumberOfEmployees__c : 0;
    System.debug('  ' + pcp.Product.Name.rightPad(30) + ' | ' + pcp.Product.ProductCode.rightPad(20) + ' | Min=' + minEmp + ' | PDQs=' + pdqCount);
}
