public class ProductDiscoveryAdditionalContextData {
    
    public class FlowInput {
        @invocableVariable(required=false) public String objectApiName;
        @invocableVariable(required=false) public String recordId;
    }
    
    public class FlowOutput {
        @invocableVariable public runtime_industries_cpq.ContextDataInput[] additionalContextData;
    }
    
    @invocableMethod(label='Generate JSON' description='Generates additional Context data JSON for Quote node')
    public static List<FlowOutput> generateJSON(List<FlowInput> inputs) {

        System.debug('=== ProductDiscoveryAdditionalContextData START ===');

        String apiName = null;
        String recId = null;

        for (FlowInput input : inputs) {
            apiName = input.objectApiName;
            recId = input.recordId;
            System.debug('INPUT - objectApiName: ' + apiName);
            System.debug('INPUT - recordId: ' + recId);
        }

        List<runtime_industries_cpq.ContextDataInput> lstAdditionalContextData = new List<runtime_industries_cpq.ContextDataInput>();

        // Quote node - pass the quote ID and related fields
        runtime_industries_cpq.ContextDataInput quoteData = new runtime_industries_cpq.ContextDataInput();
        quoteData.nodeName = apiName;
        quoteData.nodeData = new Map<String, Object>();
        quoteData.nodeData.put('id', recId);

        if (String.isNotBlank(recId)) {
            try {
                Quote q = [SELECT Id, Pricebook2Id, AccountId, Account.NumberOfEmployees, Account.Industry
                           FROM Quote WHERE Id = :recId LIMIT 1];

                if (q.Pricebook2Id != null) {
                    quoteData.nodeData.put('Pricebook2Id', q.Pricebook2Id);
                    System.debug('CONTEXT - Pricebook2Id: ' + q.Pricebook2Id);
                }
                if (q.AccountId != null) {
                    quoteData.nodeData.put('AccountId', q.AccountId);
                    System.debug('CONTEXT - AccountId: ' + q.AccountId);
                }

                lstAdditionalContextData.add(quoteData);

                // Account node - pass employee count and industry for qualification
                if (q.AccountId != null) {
                    runtime_industries_cpq.ContextDataInput accountData = new runtime_industries_cpq.ContextDataInput();
                    accountData.nodeName = 'Account';
                    accountData.nodeData = new Map<String, Object>();
                    accountData.nodeData.put('id', q.AccountId);
                    accountData.nodeData.put('NumberOfEmployees', q.Account.NumberOfEmployees);
                    accountData.nodeData.put('Industry', q.Account.Industry);
                    lstAdditionalContextData.add(accountData);
                    System.debug('CONTEXT - Account: ' + q.Account.Industry + ', Employees: ' + q.Account.NumberOfEmployees);
                }
            } catch (Exception e) {
                System.debug('Error loading Quote context: ' + e.getMessage());
                lstAdditionalContextData.add(quoteData);
            }
        } else {
            lstAdditionalContextData.add(quoteData);
            System.debug('WARNING: recordId is blank');
        }

        FlowOutput output = new FlowOutput();
        output.additionalContextData = lstAdditionalContextData;

        System.debug('CONTEXT nodes count: ' + lstAdditionalContextData.size());
        System.debug('=== ProductDiscoveryAdditionalContextData END ===');
        return new List<FlowOutput>{ output };
    }
}