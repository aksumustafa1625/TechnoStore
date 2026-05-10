// Check if BrowseProductsCtxDefinition has Industry attribute bound to Account.Industry

Id ctxId = '11Oaj000000whZFEAY';

System.debug('======== ContextAttribute records on BrowseProductsCtxDefinition ========');
for (ContextAttribute ca : [
    SELECT FIELDS(STANDARD)
    FROM ContextAttribute
    WHERE ContextDefinitionId = :ctxId
    ORDER BY Id
]) {
    System.debug(ca);
}

System.debug('======== ContextAttributeMapping for Industry-related attrs ========');
for (ContextAttributeMapping cam : [
    SELECT Id, ContextAttribute.DeveloperName, NodeType, RelatedField, ProcessType
    FROM ContextAttributeMapping
    WHERE ContextAttribute.ContextDefinitionId = :ctxId
      AND (ContextAttribute.DeveloperName LIKE '%Industry%' OR ContextAttribute.DeveloperName LIKE '%industry%')
]) {
    System.debug(cam);
}

System.debug('======== ContextTag records (where attributes get values) ========');
for (ContextTag ct : [
    SELECT Id, ContextAttribute.DeveloperName, NodeId, FieldName, ProcessType
    FROM ContextTag
    WHERE ContextAttribute.ContextDefinitionId = :ctxId
      AND ContextAttribute.DeveloperName LIKE '%ndustry%'
]) {
    System.debug(ct);
}
