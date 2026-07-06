// Read-only RLM / Salesforce Pricing diagnostic.
// No DML, no callout, no cache refresh. Safe to run in Anonymous Apex.

public class ReadOnlyRlmDiag {
    private Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

    private Boolean hasObject(String objectName) {
        return gd.containsKey(objectName);
    }

    private Set<String> fieldNames(String objectName) {
        if (!hasObject(objectName)) return new Set<String>();
        return gd.get(objectName).getDescribe().fields.getMap().keySet();
    }

    private List<String> existingFields(String objectName, List<String> wanted) {
        Set<String> available = fieldNames(objectName);
        List<String> fields = new List<String>();
        for (String f : wanted) {
            if (available.contains(f.toLowerCase()) || available.contains(f)) {
                fields.add(f);
            }
        }
        if (!fields.contains('Id') && available.contains('Id')) fields.add(0, 'Id');
        return fields;
    }

    private void dumpQuery(String label, String objectName, List<String> wantedFields, String whereClause, String orderClause, Integer limitSize) {
        System.debug('===== ' + label + ' =====');
        if (!hasObject(objectName)) {
            System.debug('OBJECT_NOT_FOUND: ' + objectName);
            return;
        }
        List<String> fields = existingFields(objectName, wantedFields);
        if (fields.isEmpty()) {
            System.debug('NO_FIELDS_FOUND_FOR: ' + objectName);
            return;
        }
        String soql = 'SELECT ' + String.join(fields, ',') + ' FROM ' + objectName;
        if (String.isNotBlank(whereClause)) soql += ' WHERE ' + whereClause;
        if (String.isNotBlank(orderClause)) soql += ' ORDER BY ' + orderClause;
        if (limitSize != null && limitSize > 0) soql += ' LIMIT ' + limitSize;
        System.debug('SOQL: ' + soql);
        try {
            List<SObject> rows = Database.query(soql);
            System.debug('ROW_COUNT=' + rows.size());
            for (SObject row : rows) {
                System.debug(row);
            }
        } catch (Exception e) {
            System.debug('QUERY_FAILED: ' + e.getTypeName() + ' | ' + e.getMessage());
        }
    }

    private void dumpObjectCandidates(String token) {
        System.debug('===== OBJECTS CONTAINING "' + token + '" =====');
        List<String> names = new List<String>();
        for (String n : gd.keySet()) {
            if (n != null && n.toLowerCase().contains(token.toLowerCase())) names.add(n);
        }
        names.sort();
        System.debug(names);
    }

    public void run() {
        System.debug('############################################################');
        System.debug('RLM PRICING CONTEXT READ-ONLY DIAG START');
        System.debug('RunAt=' + System.now());
        System.debug('############################################################');

        dumpObjectCandidates('Context');
        dumpObjectCandidates('Procedure');
        dumpObjectCandidates('Pricing');

        dumpQuery(
            'ContextDefinition target records',
            'ContextDefinition',
            new List<String>{'Id','DeveloperName','MasterLabel','Name','Status','CreatedDate','LastModifiedDate'},
            '(DeveloperName IN (\'RLM_SalesTransactionContext\',\'RevSalesTransactionContext\',\'BrowseProductsCtxDefinition\',\'Custom_ContractsContext\') OR Name IN (\'RLM_SalesTransactionContext\',\'RevSalesTransactionContext\',\'BrowseProductsCtxDefinition\',\'Custom_ContractsContext\'))',
            'DeveloperName',
            50
        );

        dumpQuery(
            'ContextDefinitionVersion recent target versions',
            'ContextDefinitionVersion',
            new List<String>{'Id','ContextDefinitionId','VersionNumber','IsActive','Status','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            30
        );

        dumpQuery(
            'ContextDefinitionSync recent records',
            'ContextDefinitionSync',
            new List<String>{'Id','ContextDefinitionId','ContextDefinitionVersionId','Status','ErrorMessage','CreatedDate','LastModifiedDate','CompletedDate','LastSuccessfulSyncDate'},
            null,
            'CreatedDate DESC',
            30
        );

        dumpQuery(
            'CalculationProcedure records',
            'CalculationProcedure',
            new List<String>{'Id','Name','UniqueName','DeveloperName','Status','IsActive','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            50
        );

        dumpQuery(
            'CalculationProcedureVersion records',
            'CalculationProcedureVersion',
            new List<String>{'Id','CalculationProcedureId','VersionNumber','IsEnabled','Rank','Status','StartDateTime','EndDateTime','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            50
        );

        dumpQuery(
            'ContextMapping / context mappings',
            'ContextMapping',
            new List<String>{'Id','Name','DeveloperName','ContextDefinitionId','ContextDefinitionVersionId','Status','IsActive','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            50
        );

        dumpQuery(
            'ContextNodeMapping recent records',
            'ContextNodeMapping',
            new List<String>{'Id','Name','ContextMappingId','SourceObjectName','TargetObjectName','SourceNodeName','TargetNodeName','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            80
        );

        dumpQuery(
            'ProcedurePlanDefinitionVersion recent',
            'ProcedurePlanDefinitionVersion',
            new List<String>{'Id','Name','ProcedurePlanDefinitionId','IsActive','Status','VersionNumber','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            30
        );

        dumpQuery(
            'ProcedurePlanOption recent',
            'ProcedurePlanOption',
            new List<String>{'Id','Name','ProcedurePlanDefinitionVersionId','ProcedureName','ProcedureId','SectionId','SectionName','SectionType','Priority','IsActive','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            50
        );

        String quoteWhere = 'Id IN (\'0Q0aj000002hDwyCAE\',\'0Q0aj000002hDwzCAE\')';
        dumpQuery(
            'Demo Quote 4 and 5 state',
            'Quote',
            new List<String>{'Id','Name','Status','CalculationStatus','ValidationResult','LastPricedDate','Pricebook2Id','CurrencyIsoCode','TotalPrice','Tax','GrandTotal','Subtotal','CreatedDate','LastModifiedDate'},
            quoteWhere,
            'Name',
            20
        );

        dumpQuery(
            'QuoteLineItem state for Demo Quote 4 and 5',
            'QuoteLineItem',
            new List<String>{'Id','QuoteId','Product2Id','Product2.Name','Product2.ProductCode','Product2.Type','PricebookEntryId','Quantity','UnitPrice','ListPrice','SalesPrice','NetUnitPrice','NetTotalPrice','Subtotal','TotalPrice','TotalLineAmount','ValidationResult','ParentQuoteLineItemId','CreatedDate','LastModifiedDate'},
            'QuoteId IN (\'0Q0aj000002hDwyCAE\',\'0Q0aj000002hDwzCAE\')',
            'QuoteId, CreatedDate',
            100
        );

        dumpQuery(
            'QuoteLineRelationship for Demo Quote 4 and 5 lines',
            'QuoteLineRelationship',
            new List<String>{'Id','MainQuoteLineId','AssociatedQuoteLineId','RootQuoteLineId','ProductRelatedComponentId','ProductRelationshipTypeId','AssociatedQuoteLinePricing','AssociatedQuantScaleMethod','IsPriceInclusive','CreatedDate','LastModifiedDate'},
            null,
            'CreatedDate DESC',
            100
        );

        dumpQuery(
            'QuoteLineItemAttribute for Demo Quote 4 and 5 lines',
            'QuoteLineItemAttribute',
            new List<String>{'Id','QuoteLineItemId','AttributeDefinitionId','AttributeName','AttributeValue','AttributePicklistValueId','IsPriceImpacting','CreatedDate','LastModifiedDate'},
            null,
            'CreatedDate DESC',
            120
        );

        dumpQuery(
            'QuoteLinePriceAdjustment for Demo Quote 4 and 5 lines',
            'QuoteLinePriceAdjustment',
            new List<String>{'Id','QuoteLineItemId','AdjustmentSource','AdjustmentType','AdjustmentAmountScope','AdjustmentValue','TotalAmount','Priority','Description','CreatedDate','LastModifiedDate'},
            null,
            'CreatedDate DESC',
            100
        );

        dumpQuery(
            'Recent RevenueTransactionErrorLog',
            'RevenueTransactionErrorLog',
            new List<String>{'Id','Name','RecordId','ContextDefinitionId','ContextDefinitionVersionId','ErrorCode','ErrorMessage','StackTrace','CreatedDate','LastModifiedDate'},
            null,
            'CreatedDate DESC',
            50
        );

        System.debug('############################################################');
        System.debug('RLM PRICING CONTEXT READ-ONLY DIAG END');
        System.debug('############################################################');
    }
}

new ReadOnlyRlmDiag().run();
