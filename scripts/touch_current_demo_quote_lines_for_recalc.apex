// Touch the current demo quote lines to trigger RLM recalculation after disabling
// Quote Estimated Tax CPQ.

Set<Id> demoQuoteIds = new Set<Id>{
    '0Q0aj000002hDwvCAE', // Demo Quote 1
    '0Q0aj000002hDwwCAE', // Demo Quote 2
    '0Q0aj000002hDwxCAE', // Demo Quote 3
    '0Q0aj000002hDwyCAE', // Demo Quote 4
    '0Q0aj000002hDwzCAE'  // Demo Quote 5
};

List<QuoteLineItem> qlis = [
    SELECT Id
    FROM QuoteLineItem
    WHERE QuoteId IN :demoQuoteIds
];

System.debug('Touching QLIs: ' + qlis.size());
update qlis;

for (Quote q : [
    SELECT Id, Name, CalculationStatus
    FROM Quote
    WHERE Id IN :demoQuoteIds
    ORDER BY Name
]) {
    System.debug(
        q.Name +
        ' CalculationStatus=' + q.CalculationStatus
    );
}
