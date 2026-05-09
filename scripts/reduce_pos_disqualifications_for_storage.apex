// Reduce POS disqualification rows to the industries used in the demo to free
// Developer Edition data storage. Keeps Hamburg/Frankfurt/Munich hidden.

Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};
Set<String> keepIndustries = new Set<String>{'Technology', 'Finance', 'Manufacturing', 'Other'};

Set<Id> posProductIds = new Set<Id>();
for (Product2 product : [
    SELECT Id
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    posProductIds.add(product.Id);
}

List<ProductDisqualification> toDelete = [
    SELECT Id, Industry__c
    FROM ProductDisqualification
    WHERE ProductId IN :posProductIds
    AND Industry__c NOT IN :keepIndustries
];
if (!toDelete.isEmpty()) delete toDelete;

System.debug('Deleted extra POS disqualification rows: ' + toDelete.size());
