// Diagnose: Why does the Pricing DT fail to find prices?
// DT: Price_Book_Entry_Decision_Table_v2 (0lDaj000000DanGEAS)
// Inputs needed: Product2Id, Pricebook2Id, ProductSellingModelId, Quantity

String quoteId = '0Q0aj0000028XorCAE'; // Test Quote 13
Quote q = [SELECT Id, Name, Pricebook2Id FROM Quote WHERE Id = :quoteId];
System.debug('=== Quote: ' + q.Name + ' | PB: ' + q.Pricebook2Id);

// Get Laptop products
List<ProductCategoryProduct> pcps = [
    SELECT ProductId FROM ProductCategoryProduct
    WHERE ProductCategoryId = '0ZGaj000000LPRdGAO' LIMIT 5
];

for (ProductCategoryProduct pcp : pcps) {
    Id prodId = pcp.ProductId;

    // Find PBE for this product + this pricebook
    List<PricebookEntry> pbes = [
        SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive,
               ProductSellingModelId, ProductSellingModel.Name,
               ProductSellingModel.SellingModelType
        FROM PricebookEntry
        WHERE Product2Id = :prodId
        AND Pricebook2Id = :q.Pricebook2Id
        AND IsActive = true
    ];

    Product2 prod = [SELECT Id, Name FROM Product2 WHERE Id = :prodId];
    System.debug('--- Product: ' + prod.Name + ' (' + prodId + ')');
    System.debug('    PBE count for Quote PB: ' + pbes.size());

    for (PricebookEntry pbe : pbes) {
        System.debug('    PBE: Price=' + pbe.UnitPrice +
                     ' | PSM=' + pbe.ProductSellingModelId +
                     ' | PSMName=' + pbe.ProductSellingModel.Name +
                     ' | Type=' + pbe.ProductSellingModel.SellingModelType);
    }

    // Also check Standard PB entries
    List<PricebookEntry> stdPbes = [
        SELECT Id, UnitPrice, ProductSellingModelId
        FROM PricebookEntry
        WHERE Product2Id = :prodId
        AND Pricebook2.IsStandard = true
        AND IsActive = true
    ];
    System.debug('    Standard PB entries: ' + stdPbes.size());
}
