// Step 1: Repurpose VR Headset as POS Solutions and free storage by deleting
// old category-product links before inserting POS links in a separate step.

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

List<ProductCategoryProduct> linksToDelete = [
    SELECT Id
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :targetCategory.Id
    OR ProductId IN :posProductIds
];
if (!linksToDelete.isEmpty()) delete linksToDelete;

for (ProductCategoryQualification pcq : [
    SELECT Id, EffectiveFromDate, EffectiveToDate
    FROM ProductCategoryQualification
    WHERE CategoryId = :targetCategory.Id
]) {
    pcq.EffectiveFromDate = Date.today().addDays(-1);
    pcq.EffectiveToDate = Date.newInstance(2099, 12, 31);
    update pcq;
}

System.debug('Repurposed category: ' + targetCategory.Id + ' -> POS Solutions');
System.debug('Deleted links to free storage: ' + linksToDelete.size());
