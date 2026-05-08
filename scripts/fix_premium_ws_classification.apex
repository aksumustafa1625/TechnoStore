// Fix two structural mismatches that prevent Premium Workstation Pro from appearing
// in the Workstation category alongside RenderStation Ultra and WorkStation X Pro:
//   1. Type = 'Base' -> null (others have null)
//   2. BasedOnId = Laptop -> Computer (matches the existing Workstation products)

Product2 prod = [SELECT Id, Type, BasedOnId FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1];
System.debug('BEFORE: Type=' + prod.Type + ' | BasedOnId=' + prod.BasedOnId);

// Type is not writeable on update; only BasedOnId can be changed
prod.BasedOnId = '11Baj000014WD4EEAW';   // Computer classification (used by both existing workstations)
update prod;

Product2 verify = [SELECT Type, BasedOnId, BasedOn.Name FROM Product2 WHERE Id = :prod.Id];
System.debug('AFTER:  Type=' + verify.Type + ' | BasedOn=' + verify.BasedOn.Name);
