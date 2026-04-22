for (QuoteLineItem q : [SELECT Id, QuoteId, LineNumber, Product2.Name, Product2Id, Description FROM QuoteLineItem WHERE QuoteId = '0Q0aj000002CmqvCAC']) {
    System.debug('QLI='+q.Id+' | LineNumber='+q.LineNumber+' | Product2.Name='+q.Product2.Name+' | Product2Id='+q.Product2Id);
}
// Check sales contract lines created anywhere for this org recently
for (SalesContractLine scl : [SELECT Id, Name, ContractId, Product2.Name, Contract.SourceQuoteId FROM SalesContractLine ORDER BY CreatedDate DESC LIMIT 5]) {
    System.debug('SCL='+scl.Id+' | Name='+scl.Name+' | Contract='+scl.ContractId);
}