// Step 2: Insert POS product links into the repurposed POS Solutions category.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';
Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

ProductCategory targetCategory = [
    SELECT Id, Name, CatalogId, Catalog.Name
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'POS Solutions'
    LIMIT 1
];

List<ProductCategoryProduct> linksToInsert = new List<ProductCategoryProduct>();
for (Product2 product : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    if (!product.IsActive) {
        product.IsActive = true;
        update product;
    }
    linksToInsert.add(new ProductCategoryProduct(
        ProductCategoryId = targetCategory.Id,
        ProductId = product.Id
    ));
}
insert linksToInsert;

System.debug('Inserted POS links: ' + linksToInsert.size());
System.debug('======== POS Solutions links ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
