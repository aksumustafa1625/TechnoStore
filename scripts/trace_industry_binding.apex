// Trace Industry context attribute → ContextNode → ContextDefinition → mapping to Account.Industry

Id industryAttrId = '11naj000002b68ZAAQ';
Id contextNodeId  = '11oaj00000APAJOAA5';

System.debug('======== ContextNode 11oaj00000APAJOAA5 ========');
for (ContextNode cn : [SELECT FIELDS(STANDARD) FROM ContextNode WHERE Id = :contextNodeId LIMIT 1]) {
    System.debug(cn);
}

System.debug('======== ContextTag for Industry attribute (where it gets the value from) ========');
for (ContextTag ct : [SELECT FIELDS(STANDARD) FROM ContextTag WHERE ContextAttributeId = :industryAttrId LIMIT 50]) {
    System.debug(ct);
}

System.debug('======== ContextAttributeMapping for Industry attribute ========');
for (ContextAttributeMapping cam : [SELECT FIELDS(STANDARD) FROM ContextAttributeMapping WHERE ContextAttributeId = :industryAttrId LIMIT 50]) {
    System.debug(cam);
}

System.debug('======== ContextAttrHydrationDetail (sample) ========');
for (ContextAttrHydrationDetail h : [SELECT FIELDS(STANDARD) FROM ContextAttrHydrationDetail LIMIT 5]) {
    System.debug(h);
}
