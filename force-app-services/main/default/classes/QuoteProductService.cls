/**
 * Custom service to add products to quotes with pricing,
 * bypassing the EPC pricing procedure that fails.
 * Works with Browse Catalog (procedures disabled) as a direct Add-to-Quote solution.
 */
public with sharing class QuoteProductService {

    public class ProductWithPrice {
        @InvocableVariable public String productId;
        @InvocableVariable public String productName;
        @InvocableVariable public Decimal unitPrice;
        @InvocableVariable public String pricebookEntryId;
        @InvocableVariable public String sellingModelId;
        @InvocableVariable public String sellingModelName;
    }

    public class AddToQuoteInput {
        @InvocableVariable(required=true) public String quoteId;
        @InvocableVariable(required=true) public String productId;
        @InvocableVariable public Decimal quantity;
    }

    public class AddToQuoteOutput {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public String quoteLineItemId;
    }

    /**
     * Add a product to a quote - looks up PricebookEntry automatically
     */
    @InvocableMethod(label='Add Product to Quote with Price' description='Adds a product to a quote by looking up the correct PricebookEntry price')
    public static List<AddToQuoteOutput> addProductToQuote(List<AddToQuoteInput> inputs) {
        List<AddToQuoteOutput> results = new List<AddToQuoteOutput>();

        for (AddToQuoteInput input : inputs) {
            AddToQuoteOutput output = new AddToQuoteOutput();
            try {
                Decimal qty = (input.quantity != null && input.quantity > 0) ? input.quantity : 1;

                // Get Quote's Pricebook
                Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :input.quoteId LIMIT 1];
                if (q.Pricebook2Id == null) {
                    output.success = false;
                    output.message = 'Quote does not have a Pricebook assigned.';
                    results.add(output);
                    continue;
                }

                // Find PricebookEntry for this product in the Quote's Pricebook
                List<PricebookEntry> pbes = [
                    SELECT Id, UnitPrice, ProductSellingModelId
                    FROM PricebookEntry
                    WHERE Product2Id = :input.productId
                    AND Pricebook2Id = :q.Pricebook2Id
                    AND IsActive = true
                    LIMIT 1
                ];

                if (pbes.isEmpty()) {
                    // Fallback: try Standard Pricebook
                    pbes = [
                        SELECT Id, UnitPrice, ProductSellingModelId
                        FROM PricebookEntry
                        WHERE Product2Id = :input.productId
                        AND Pricebook2.IsStandard = true
                        AND IsActive = true
                        LIMIT 1
                    ];
                }

                if (pbes.isEmpty()) {
                    output.success = false;
                    output.message = 'No PricebookEntry found for this product.';
                    results.add(output);
                    continue;
                }

                PricebookEntry pbe = pbes[0];

                // Create QuoteLineItem
                QuoteLineItem qli = new QuoteLineItem();
                qli.QuoteId = input.quoteId;
                qli.Product2Id = input.productId;
                qli.PricebookEntryId = pbe.Id;
                qli.Quantity = qty;
                qli.UnitPrice = pbe.UnitPrice;
                insert qli;

                output.success = true;
                output.message = 'Product added successfully. Price: $' + pbe.UnitPrice;
                output.quoteLineItemId = qli.Id;

            } catch (Exception e) {
                output.success = false;
                output.message = 'Error: ' + e.getMessage();
            }
            results.add(output);
        }
        return results;
    }

    /**
     * AuraEnabled method for LWC - get products with prices for a quote
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getProductsWithPrices(String quoteId, String categoryId) {
        Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :quoteId];

        List<ProductCategoryProduct> pcps = [
            SELECT ProductId, Product.Name, Product.Description
            FROM ProductCategoryProduct
            WHERE ProductCategoryId = :categoryId
            ORDER BY Product.Name
        ];

        Set<Id> prodIds = new Set<Id>();
        for (ProductCategoryProduct pcp : pcps) prodIds.add(pcp.ProductId);

        Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, UnitPrice, ProductSellingModelId, ProductSellingModel.Name
            FROM PricebookEntry
            WHERE Product2Id IN :prodIds
            AND Pricebook2Id = :q.Pricebook2Id
            AND IsActive = true
        ]) {
            pbeMap.put(pbe.Product2Id, pbe);
        }

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (ProductCategoryProduct pcp : pcps) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('productId', pcp.ProductId);
            row.put('productName', pcp.Product.Name);
            row.put('description', pcp.Product.Description);

            PricebookEntry pbe = pbeMap.get(pcp.ProductId);
            if (pbe != null) {
                row.put('unitPrice', pbe.UnitPrice);
                row.put('pricebookEntryId', pbe.Id);
                row.put('hasPrice', true);
            } else {
                row.put('unitPrice', 0);
                row.put('hasPrice', false);
            }
            results.add(row);
        }
        return results;
    }

    /**
     * AuraEnabled method - add product to quote directly
     */
    @AuraEnabled
    public static Map<String, Object> addProductToQuoteDirect(String quoteId, String productId, Decimal quantity) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            AddToQuoteInput input = new AddToQuoteInput();
            input.quoteId = quoteId;
            input.productId = productId;
            input.quantity = quantity;

            List<AddToQuoteOutput> outputs = addProductToQuote(new List<AddToQuoteInput>{ input });
            AddToQuoteOutput output = outputs[0];

            result.put('success', output.success);
            result.put('message', output.message);
            result.put('quoteLineItemId', output.quoteLineItemId);
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }
}
