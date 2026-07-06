ProductAttributeDefinition screenPad = [
    SELECT Id, Product2.Name, AttributeDefinition.Name, Sequence
    FROM ProductAttributeDefinition
    WHERE Product2Id = '01taj00000Qp7IFAAZ'
      AND AttributeDefinitionId = '0tjaj000000FbXHAA0'
    LIMIT 1
];

if (screenPad.Sequence != 4) {
    screenPad.Sequence = 4;
    update screenPad;
}

System.debug('HOME_SCREEN_PAD_SEQUENCE=' + screenPad.Sequence);
