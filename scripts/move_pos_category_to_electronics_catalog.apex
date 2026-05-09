// Move the existing POS Solutions category into the main Electronics catalog.
//
// This avoids creating a new category, which can fail in a storage-limited
// Developer Edition org, and makes POS Solutions appear in the same Browse
// Catalog category list as Computers & Laptops.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';

ProductCategory posCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE Name = 'POS Solutions'
    LIMIT 1
];

System.debug('Before: ' + posCategory.Id + ' | ' + posCategory.Name + ' | Catalog=' + posCategory.Catalog.Name);

if (posCategory.CatalogId != ELECTRONICS_CATALOG_ID) {
    posCategory.CatalogId = ELECTRONICS_CATALOG_ID;
    update posCategory;
}

ProductCategory afterCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE Id = :posCategory.Id
];
System.debug('After: ' + afterCategory.Id + ' | ' + afterCategory.Name + ' | Catalog=' + afterCategory.Catalog.Name);

System.debug('======== POS category products ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :afterCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
