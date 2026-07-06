List<String> qliFields = new List<String>{
    'UnitPrice',
    'ListPrice',
    'Subtotal',
    'TotalPrice',
    'NetUnitPrice',
    'NetTotalPrice',
    'ValidationResult',
    'PriceWaterfallIdentifier',
    'ProductSellingModelId',
    'BillingFrequency'
};

Map<String, Schema.SObjectField> qliFieldMap = Schema.SObjectType.QuoteLineItem.fields.getMap();
for (String fieldName : qliFields) {
    Schema.DescribeFieldResult d = qliFieldMap.get(fieldName).getDescribe();
    System.debug('QLI_FIELD ' + fieldName + ' createable=' + d.isCreateable() + ' updateable=' + d.isUpdateable() + ' type=' + d.getType());
    if (d.getType() == Schema.DisplayType.Picklist) {
        List<String> activeValues = new List<String>();
        for (Schema.PicklistEntry entry : d.getPicklistValues()) {
            if (entry.isActive()) activeValues.add(entry.getValue());
        }
        System.debug('QLI_PICKLIST ' + fieldName + '=' + String.join(activeValues, ','));
    }
}

List<String> quoteFields = new List<String>{
    'CalculationStatus',
    'ValidationResult',
    'LastPricedDate',
    'TotalPrice',
    'TotalPriceOverride',
    'Tax',
    'GrandTotal'
};

Map<String, Schema.SObjectField> quoteFieldMap = Schema.SObjectType.Quote.fields.getMap();
for (String fieldName : quoteFields) {
    Schema.DescribeFieldResult d = quoteFieldMap.get(fieldName).getDescribe();
    System.debug('QUOTE_FIELD ' + fieldName + ' createable=' + d.isCreateable() + ' updateable=' + d.isUpdateable() + ' type=' + d.getType());
    if (d.getType() == Schema.DisplayType.Picklist) {
        List<String> activeValues = new List<String>();
        for (Schema.PicklistEntry entry : d.getPicklistValues()) {
            if (entry.isActive()) activeValues.add(entry.getValue());
        }
        System.debug('QUOTE_PICKLIST ' + fieldName + '=' + String.join(activeValues, ','));
    }
}
