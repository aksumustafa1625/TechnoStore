// Add a Retail-only POS category to the main Electronics catalog.
//
// The Product Discovery flow opens TechStore Electronics Catalog directly.
// This creates a POS Solutions category inside that catalog and links the
// existing POS products to it. Product-level disqualification hides those
// products for non-retail accounts; the category should disappear when empty.

final Id ELECTRONICS_CATALOG_ID = '0ZSaj000000KBlhGAG';

Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

List<ProductCategory> existingCategories = [
    SELECT Id, Name, CatalogId
    FROM ProductCategory
    WHERE CatalogId = :ELECTRONICS_CATALOG_ID
    AND Name = 'POS Solutions'
    LIMIT 1
];

ProductCategory posCategory;
if (existingCategories.isEmpty()) {
    posCategory = new ProductCategory(
        Name = 'POS Solutions',
        CatalogId = ELECTRONICS_CATALOG_ID
    );
    insert posCategory;
    System.debug('Created Electronics POS category: ' + posCategory.Id);
} else {
    posCategory = existingCategories[0];
    System.debug('Reusing Electronics POS category: ' + posCategory.Id);
}

List<ProductCategoryQualification> existingPcqs = [
    SELECT Id, CategoryId, EffectiveFromDate, EffectiveToDate
    FROM ProductCategoryQualification
    WHERE CategoryId = :posCategory.Id
];
if (existingPcqs.isEmpty()) {
    insert new ProductCategoryQualification(
        CategoryId = posCategory.Id,
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    );
    System.debug('Created ProductCategoryQualification for Electronics POS category');
} else {
    for (ProductCategoryQualification pcq : existingPcqs) {
        pcq.EffectiveFromDate = Date.today().addDays(-1);
        pcq.EffectiveToDate = Date.newInstance(2099, 12, 31);
    }
    update existingPcqs;
    System.debug('Updated ProductCategoryQualification for Electronics POS category');
}

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 product : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    product.IsActive = true;
    productsByCode.put(product.ProductCode, product);
}
if (!productsByCode.isEmpty()) update productsByCode.values();

Set<Id> productIds = new Set<Id>();
for (Product2 product : productsByCode.values()) productIds.add(product.Id);

Set<Id> alreadyLinkedProductIds = new Set<Id>();
for (ProductCategoryProduct pcp : [
    SELECT ProductId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :posCategory.Id
    AND ProductId IN :productIds
]) {
    alreadyLinkedProductIds.add(pcp.ProductId);
}

List<ProductCategoryProduct> linksToInsert = new List<ProductCategoryProduct>();
for (Product2 product : productsByCode.values()) {
    if (!alreadyLinkedProductIds.contains(product.Id)) {
        linksToInsert.add(new ProductCategoryProduct(
            ProductCategoryId = posCategory.Id,
            ProductId = product.Id
        ));
    }
}
if (!linksToInsert.isEmpty()) insert linksToInsert;

System.debug('POS products linked to Electronics POS category: inserted=' + linksToInsert.size());
System.debug('======== Electronics POS category products ========');
for (ProductCategoryProduct pcp : [
    SELECT Product.Name, Product.ProductCode, ProductCategory.Name, ProductCategory.Catalog.Name
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :posCategory.Id
    ORDER BY Product.Name
]) {
    System.debug(pcp.Product.ProductCode + ' | ' + pcp.Product.Name + ' | ' + pcp.ProductCategory.Catalog.Name + ' / ' + pcp.ProductCategory.Name);
}
