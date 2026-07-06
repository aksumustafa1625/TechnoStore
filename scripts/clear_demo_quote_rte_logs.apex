Set<Id> quoteIds = new Set<Id>{
    '0Q0aj000002hDwyCAE', // Demo Quote 4
    '0Q0aj000002hDwzCAE'  // Demo Quote 5
};

List<RevenueTransactionErrorLog> logsToDelete = [
    SELECT Id, ErrorLogNumber, Category
    FROM RevenueTransactionErrorLog
    WHERE PrimaryRecordId IN :quoteIds
       OR PrimaryRecord2Id IN :quoteIds
];

Database.deleteImmediate(logsToDelete);

System.debug('RTE_LOGS_DELETED=' + logsToDelete.size());
