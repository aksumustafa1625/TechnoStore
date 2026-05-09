// Repurpose "VR Headset" as "POS Solutions" without inserting new rows.
// This is designed for a storage-limited Developer Edition org.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';
Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

ProductCategory targetCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'VR Headset'
    LIMIT 1
];

targetCategory.Name = 'POS Solutions';
update targetCategory;

Set<Id> posProductIds = new Set<Id>();
for (Product2 product : [
    SELECT Id
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    posProductIds.add(product.Id);
}

// Remove the old VR products from the repurposed category.
List<ProductCategoryProduct> oldVrLinks = [
    SELECT Id
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    AND ProductId NOT IN :posProductIds
];
if (!oldVrLinks.isEmpty()) delete oldVrLinks;

// Move existing POS product links from POS Catalog to this category.
List<ProductCategoryProduct> posLinks = [
    SELECT Id, ProductId, Product.Name, Product.ProductCode, ProductCategoryId, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductId IN :posProductIds
];
for (ProductCategoryProduct link : posLinks) {
    link.ProductCategoryId = targetCategory.Id;
}
if (!posLinks.isEmpty()) update posLinks;

// Keep category qualification active; update only, because a record already
// exists for the old VR category in this org.
for (ProductCategoryQualification pcq : [
    SELECT Id, EffectiveFromDate, EffectiveToDate
    FROM ProductCategoryQualification
    WHERE CategoryId = :targetCategory.Id
]) {
    pcq.EffectiveFromDate = Date.today().addDays(-1);
    pcq.EffectiveToDate = Date.newInstance(2099, 12, 31);
    update pcq;
}

System.debug('Deleted old VR links: ' + oldVrLinks.size());
System.debug('Moved POS links: ' + posLinks.size());
System.debug('======== New POS Solutions links ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
