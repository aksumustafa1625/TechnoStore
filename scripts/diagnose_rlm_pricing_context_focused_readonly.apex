// Focused read-only RLM pricing diagnostic.
// No DML, no callouts. Prints the exact context/procedure/quote facts we need.

public class FocusedRlmDiag {
    private Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

    private Boolean hasObj(String objName) {
        return gd.containsKey(objName);
    }

    private Map<String, Schema.SObjectField> fmap(String objName) {
        if (!hasObj(objName)) return new Map<String, Schema.SObjectField>();
        return gd.get(objName).getDescribe().fields.getMap();
    }

    private Boolean hasField(String objName, String fieldName) {
        Map<String, Schema.SObjectField> fields = fmap(objName);
        return fields.containsKey(fieldName) || fields.containsKey(fieldName.toLowerCase());
    }

    private List<String> keep(String objName, List<String> fields) {
        List<String> out = new List<String>();
        for (String f : fields) if (hasField(objName, f)) out.add(f);
        if (!out.contains('Id') && hasField(objName, 'Id')) out.add(0, 'Id');
        return out;
    }

    private void q(String label, String objName, List<String> fields, String whereClause, String orderBy, Integer lim) {
        System.debug('===== ' + label + ' =====');
        if (!hasObj(objName)) {
            System.debug('MISSING_OBJECT ' + objName);
            return;
        }
        List<String> selected = keep(objName, fields);
        System.debug('FIELDS=' + selected);
        String soql = 'SELECT ' + String.join(selected, ',') + ' FROM ' + objName;
        if (String.isNotBlank(whereClause)) soql += ' WHERE ' + whereClause;
        if (String.isNotBlank(orderBy)) soql += ' ORDER BY ' + orderBy;
        if (lim != null) soql += ' LIMIT ' + lim;
        System.debug('SOQL=' + soql);
        try {
            List<SObject> rows = Database.query(soql);
            System.debug('COUNT=' + rows.size());
            for (SObject r : rows) System.debug(String.valueOf(r));
        } catch (Exception e) {
            System.debug('FAILED=' + e.getTypeName() + ' | ' + e.getMessage());
        }
    }

    private void fieldList(String objName) {
        System.debug('===== FIELD LIST ' + objName + ' =====');
        if (!hasObj(objName)) {
            System.debug('MISSING_OBJECT ' + objName);
            return;
        }
        List<String> names = new List<String>();
        names.addAll(fmap(objName).keySet());
        names.sort();
        System.debug(names);
    }

    public void run() {
        System.debug('### FOCUSED RLM DIAG START ' + System.now() + ' ###');

        fieldList('ContextDefinitionSync');
        fieldList('ContextMapping');
        fieldList('PricingProcedureSetup');
        fieldList('PricingSetup');

        q(
            'Target ContextDefinitions',
            'ContextDefinition',
            new List<String>{'Id','DeveloperName','MasterLabel','CreatedDate','LastModifiedDate'},
            'DeveloperName IN (\'RLM_SalesTransactionContext\',\'RevSalesTransactionContext\',\'BrowseProductsCtxDefinition\',\'Custom_ContractsContext\')',
            'DeveloperName',
            20
        );

        q(
            'All active ContextDefinitionVersions',
            'ContextDefinitionVersion',
            new List<String>{'Id','ContextDefinitionId','VersionNumber','IsActive','Status','CreatedDate','LastModifiedDate'},
            'IsActive = true',
            'LastModifiedDate DESC',
            30
        );

        q(
            'All ContextDefinitionSync rows',
            'ContextDefinitionSync',
            new List<String>{'Id','ContextDefinitionId','ContextDefinitionVersionId','Status','ErrorMessage','Message','CreatedDate','LastModifiedDate','CompletedDate','LastSuccessfulSyncDate'},
            null,
            'CreatedDate DESC',
            50
        );

        q(
            'Revenue pricing procedure',
            'CalculationProcedure',
            new List<String>{'Id','Name','UniqueName','DeveloperName','Status','IsActive','CreatedDate','LastModifiedDate'},
            'UniqueName = \'Revenue_Management_Default_Pricing_Procedure_V1\' OR Name = \'Revenue Management Default Pricing Procedure V1\'',
            'LastModifiedDate DESC',
            10
        );

        q(
            'Revenue pricing procedure versions',
            'CalculationProcedureVersion',
            new List<String>{'Id','CalculationProcedureId','VersionNumber','IsEnabled','Rank','Status','StartDateTime','EndDateTime','CreatedDate','LastModifiedDate'},
            'CalculationProcedureId = \'0k0aj000000I52wAAC\'',
            'VersionNumber DESC',
            20
        );

        q(
            'Pricing setup-like records',
            'PricingProcedureSetup',
            new List<String>{'Id','Name','PricingProcedureId','CalculationProcedureId','CalculationProcedureVersionId','IsActive','Status','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            20
        );

        q(
            'ContextMapping records',
            'ContextMapping',
            new List<String>{'Id','Name','DeveloperName','ContextDefinitionId','ContextDefinitionVersionId','Status','IsActive','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            80
        );

        q(
            'ContextMappingIntent records',
            'ContextMappingIntent',
            new List<String>{'Id','Name','DeveloperName','ContextMappingId','ContextDefinitionId','Intent','Status','CreatedDate','LastModifiedDate'},
            null,
            'LastModifiedDate DESC',
            80
        );

        q(
            'Demo Quote 4 and 5 state',
            'Quote',
            new List<String>{'Id','Name','Status','CalculationStatus','ValidationResult','LastPricedDate','Pricebook2Id','CurrencyIsoCode','Subtotal','TotalPrice','Tax','GrandTotal','CreatedDate','LastModifiedDate'},
            'Id IN (\'0Q0aj000002hDwyCAE\',\'0Q0aj000002hDwzCAE\')',
            'Name',
            20
        );

        q(
            'Demo Quote 4 and 5 lines',
            'QuoteLineItem',
            new List<String>{'Id','QuoteId','Product2Id','Product2.Name','Product2.ProductCode','Product2.Type','PricebookEntryId','Quantity','UnitPrice','NetUnitPrice','NetTotalPrice','Subtotal','TotalPrice','ValidationResult','ParentQuoteLineItemId','CreatedDate','LastModifiedDate'},
            'QuoteId IN (\'0Q0aj000002hDwyCAE\',\'0Q0aj000002hDwzCAE\')',
            'QuoteId, CreatedDate',
            100
        );

        q(
            'Recent RTE logs',
            'RevenueTransactionErrorLog',
            new List<String>{'Id','RecordId','ContextDefinitionId','ContextDefinitionVersionId','ErrorCode','ErrorMessage','CreatedDate','LastModifiedDate'},
            null,
            'CreatedDate DESC',
            20
        );

        System.debug('### FOCUSED RLM DIAG END ###');
    }
}

new FocusedRlmDiag().run();
