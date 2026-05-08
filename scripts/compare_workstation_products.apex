// Compare Premium Workstation Pro to existing WorkStation X Pro / RenderStation Ultra
// — what fields differ that might affect catalog visibility?

List<String> codes = new List<String>{'COMP-WS-PREMIUM','COMP-WS-001','COMP-WS-002'};
for (Product2 p : [SELECT Id, Name, ProductCode, Family, Type, BasedOnId, IsActive, ConfigureDuringSale, Description
                  FROM Product2 WHERE ProductCode IN :codes]) {
    System.debug('---- ' + p.Name + ' (' + p.ProductCode + ') ----');
    System.debug('  Type=' + p.Type + ' | Family=' + p.Family + ' | IsActive=' + p.IsActive);
    System.debug('  BasedOnId=' + p.BasedOnId + ' | ConfigureDuringSale=' + p.ConfigureDuringSale);

    if (p.BasedOnId != null) {
        ProductClassification pc = [SELECT Id, Name, Status FROM ProductClassification WHERE Id = :p.BasedOnId];
        System.debug('  BasedOn classification: ' + pc.Name + ' (Status=' + pc.Status + ')');
    }

    System.debug('  ProductCategoryProduct rows:');
    for (ProductCategoryProduct pcp : [SELECT ProductCategoryId, ProductCategory.Name, ProductCategory.Catalog.Name FROM ProductCategoryProduct WHERE ProductId = :p.Id]) {
        System.debug('    ' + pcp.ProductCategory.Name + ' (in catalog: ' + (pcp.ProductCategory.Catalog != null ? pcp.ProductCategory.Catalog.Name : 'null') + ')');
    }

    System.debug('  ProductSellingModelOption rows:');
    for (ProductSellingModelOption psmo : [SELECT ProductSellingModelId, ProductSellingModel.Name, ProductSellingModel.PricingTerm FROM ProductSellingModelOption WHERE Product2Id = :p.Id]) {
        System.debug('    ' + psmo.ProductSellingModel.Name);
    }

    System.debug('  Pricebook entries:');
    for (PricebookEntry pbe : [SELECT Pricebook2.Name, UnitPrice, IsActive FROM PricebookEntry WHERE Product2Id = :p.Id]) {
        System.debug('    ' + pbe.Pricebook2.Name + ' | Price=' + pbe.UnitPrice + ' | Active=' + pbe.IsActive);
    }
}
