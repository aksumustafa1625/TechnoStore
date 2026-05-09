// Repurpose the existing "VR Headset" category in TechStore Electronics Catalog
// as "POS Solutions" for the retail-industry demo.
//
// This avoids creating new ProductCategory rows in a storage-limited Developer
// Edition org. POS products already have ProductQualification and
// ProductDisqualification records; this makes the POS category appear in the
// main Browse Catalog tree for retail accounts.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';
Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

ProductCategory targetCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'VR Headset'
    LIMIT 1
];

System.debug('Repurposing category: ' + targetCategory.Id + ' | ' + targetCategory.Name + ' | ' + targetCategory.Catalog.Name);

targetCategory.Name = 'POS Solutions';
update targetCategory;

Map<String, Product2> posProductsByCode = new Map<String, Product2>();
for (Product2 product : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    product.IsActive = true;
    posProductsByCode.put(product.ProductCode, product);
}
if (!posProductsByCode.isEmpty()) update posProductsByCode.values();

Set<Id> posProductIds = new Set<Id>();
for (Product2 product : posProductsByCode.values()) posProductIds.add(product.Id);

// Delete old VR category product links and old POS links in the separate POS Catalog.
List<ProductCategoryProduct> linksToDelete = [
    SELECT Id, ProductId, Product.Name, Product.ProductCode, ProductCategoryId, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    OR ProductId IN :posProductIds
];
if (!linksToDelete.isEmpty()) delete linksToDelete;

List<ProductCategoryProduct> linksToInsert = new List<ProductCategoryProduct>();
for (Product2 product : posProductsByCode.values()) {
    linksToInsert.add(new ProductCategoryProduct(
        ProductCategoryId = targetCategory.Id,
        ProductId = product.Id
    ));
}
if (!linksToInsert.isEmpty()) insert linksToInsert;

// Keep category qualification active.
List<ProductCategoryQualification> existingPcqs = [
    SELECT Id, EffectiveFromDate, EffectiveToDate
    FROM ProductCategoryQualification
    WHERE CategoryId = :targetCategory.Id
];
if (existingPcqs.isEmpty()) {
    insert new ProductCategoryQualification(
        CategoryId = targetCategory.Id,
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    );
} else {
    for (ProductCategoryQualification pcq : existingPcqs) {
        pcq.EffectiveFromDate = Date.today().addDays(-1);
        pcq.EffectiveToDate = Date.newInstance(2099, 12, 31);
    }
    update existingPcqs;
}

System.debug('Deleted old links: ' + linksToDelete.size());
System.debug('Inserted POS links: ' + linksToInsert.size());
System.debug('======== New POS Solutions links ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
