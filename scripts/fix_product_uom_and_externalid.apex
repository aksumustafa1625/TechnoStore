// Set QuantityUnitOfMeasure + ExternalId to match working products

Product2 prod = [SELECT Id, QuantityUnitOfMeasure, ExternalId FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1];
prod.QuantityUnitOfMeasure = 'Each';
prod.ExternalId = 'TECHSTORE-COMP-WS-PREMIUM';
update prod;

Product2 v = [SELECT QuantityUnitOfMeasure, ExternalId, Type FROM Product2 WHERE Id = :prod.Id];
System.debug('UOM=' + v.QuantityUnitOfMeasure + ' | ExternalId=' + v.ExternalId + ' | Type=' + v.Type);
