Invocable.Action a = Invocable.Action.createStandardAction('createOrUpdateAssetFromOrder');
a.setInvocationParameter('orderId', '801aj00002an6D2AAI');
try {
    List<Invocable.Action.Result> results = a.invoke();
    for (Invocable.Action.Result r : results) {
        System.debug('Success: ' + r.isSuccess());
        System.debug('Errors: ' + r.getErrors());
        System.debug('Outputs: ' + r.getOutputParameters());
    }
} catch (Exception e) {
    System.debug('EXCEPTION: ' + e.getMessage() + ' :: ' + e.getTypeName());
}
List<Asset> assets = [SELECT Id, Name, Product2.Name, Quantity, Price, Status FROM Asset WHERE AccountId='001aj00002agpI6AAI'];
System.debug('Assets on Aksu LTD: ' + assets.size());
for (Asset a2 : assets) {
    System.debug('  - ' + a2.Name + ' | Product: ' + a2.Product2.Name + ' | Qty: ' + a2.Quantity);
}
