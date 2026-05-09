// Storage-safe fallback:
// Use an existing 4-link category ("Keyboard & Mouse") as "POS Solutions" and
// update its existing ProductCategoryProduct rows to point at the 4 POS
// products. No ProductCategoryProduct inserts are required.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';
List<String> posProductCodes = new List<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

// Rename the empty POS category from the failed VR attempt so the final name is unique.
for (ProductCategory emptyPos : [
    SELECT Id, Name
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'POS Solutions'
]) {
    emptyPos.Name = 'VR Headset Archive';
    update emptyPos;
}

ProductCategory targetCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'Keyboard & Mouse'
    LIMIT 1
];

targetCategory.Name = 'POS Solutions';
update targetCategory;

List<Product2> posProducts = [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :posProductCodes
    ORDER BY ProductCode
];
for (Product2 product : posProducts) {
    if (!product.IsActive) product.IsActive = true;
}
update posProducts;

List<ProductCategoryProduct> links = [
    SELECT Id, ProductId, Product.Name, Product.ProductCode
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    ORDER BY Product.Name
];

if (links.size() < posProducts.size()) {
    System.debug('Not enough existing links to repurpose. Existing=' + links.size() + ', needed=' + posProducts.size());
} else {
    for (Integer i = 0; i < posProducts.size(); i++) {
        links[i].ProductId = posProducts[i].Id;
    }
    update links;
}

for (ProductCategoryQualification pcq : [
    SELECT Id, EffectiveFromDate, EffectiveToDate
    FROM ProductCategoryQualification
    WHERE CategoryId = :targetCategory.Id
]) {
    pcq.EffectiveFromDate = Date.today().addDays(-1);
    pcq.EffectiveToDate = Date.newInstance(2099, 12, 31);
    update pcq;
}

System.debug('Repurposed Keyboard & Mouse category: ' + targetCategory.Id + ' -> POS Solutions');
System.debug('Updated existing links: ' + Math.min(links.size(), posProducts.size()));
System.debug('======== POS Solutions links ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
