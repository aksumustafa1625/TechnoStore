// Inspect what ProcedurePlanOption records do — they may be blocking new products

System.debug('======== ProcedurePlanOption schema ========');
Map<String, Schema.SObjectField> ppoF = Schema.SObjectType.ProcedurePlanOption.fields.getMap();
for (String f : ppoF.keySet()) {
    Schema.DescribeFieldResult d = ppoF.get(f).getDescribe();
    System.debug('  ' + f + ' | ' + d.getType() + ' | RefersTo=' + d.getReferenceTo());
}

System.debug('======== Existing PPO records (full) ========');
List<String> ppoFn = new List<String>(ppoF.keySet());
String soql = 'SELECT ' + String.join(ppoFn, ',') + ' FROM ProcedurePlanOption LIMIT 20';
List<ProcedurePlanOption> ppos = Database.query(soql);
for (ProcedurePlanOption ppo : ppos) {
    System.debug('PPO Id: ' + ppo.Id);
    for (String f : ppoFn) {
        Object v = ppo.get(f);
        if (v != null) System.debug('  ' + f + ' = ' + v);
    }
    System.debug('  ----');
}

System.debug('======== ProcedurePlanCriterion records (rules in the procedures) ========');
Map<String, Schema.SObjectField> ppcF = Schema.SObjectType.ProcedurePlanCriterion.fields.getMap();
List<String> ppcFn = new List<String>(ppcF.keySet());
String ppcSoql = 'SELECT ' + String.join(ppcFn, ',') + ' FROM ProcedurePlanCriterion LIMIT 20';
List<ProcedurePlanCriterion> ppcs = Database.query(ppcSoql);
for (ProcedurePlanCriterion ppc : ppcs) {
    System.debug('PPC Id: ' + ppc.Id);
    for (String f : ppcFn) {
        Object v = ppc.get(f);
        if (v != null) System.debug('  ' + f + ' = ' + v);
    }
    System.debug('  ----');
}

System.debug('======== ProcedurePlanSection records ========');
Map<String, Schema.SObjectField> ppsF = Schema.SObjectType.ProcedurePlanSection.fields.getMap();
List<String> ppsFn = new List<String>(ppsF.keySet());
String ppsSoql = 'SELECT ' + String.join(ppsFn, ',') + ' FROM ProcedurePlanSection LIMIT 20';
List<ProcedurePlanSection> ppss = Database.query(ppsSoql);
for (ProcedurePlanSection pps : ppss) {
    System.debug('PPS Id: ' + pps.Id);
    for (String f : ppsFn) {
        Object v = pps.get(f);
        if (v != null) System.debug('  ' + f + ' = ' + v);
    }
    System.debug('  ----');
}
