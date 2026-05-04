try {
    update new ProductAttributeDefinition(Id='0v7aj000000D2lZAAS', IsPriceImpacting=false);
    System.debug('Updated successfully');
    ProductAttributeDefinition pad = [SELECT IsPriceImpacting FROM ProductAttributeDefinition WHERE Id='0v7aj000000D2lZAAS'];
    System.debug('Final IsPriceImpacting: ' + pad.IsPriceImpacting);
} catch (Exception e) {
    System.debug('ERROR: ' + e.getTypeName() + ': ' + e.getMessage());
}
