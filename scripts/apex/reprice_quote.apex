Id quoteId = [SELECT Id FROM Quote WHERE QuoteNumber = '00000075' LIMIT 1].Id;
System.debug('Quote Id: ' + quoteId);

Map<String, Object> args = new Map<String, Object>{
    'contextDefinition' => 'Transaction_Pricing_ContextMapping_Definition',
    'contextMappingName' => 'Transaction_Pricing_ContextMapping_Definition',
    'transactionObjectId' => quoteId
};

try {
    Type t = Type.forName('ConnectApi.PricingService');
    System.debug('ConnectApi.PricingService present: ' + (t != null));
} catch (Exception e) { System.debug('Type check fail: ' + e.getMessage()); }

// Try direct invocable call
List<Map<String, Object>> invocableInputs = new List<Map<String, Object>>{
    new Map<String, Object>{ 'transactionId' => quoteId }
};

try {
    List<Invocable.Action> actions = Invocable.Action.createActionList('standard:pricingCalculatePricesAction');
    System.debug('Tried pricingCalculatePricesAction');
} catch (Exception e) {
    System.debug('Invocable list fail: ' + e.getMessage());
}
