Order o = [SELECT Id, TotalAmount, TotalTaxAmount, GrandTotalAmount, TotalAmountOverride FROM Order WHERE Id = '801aj00002fQbT7AAK'];
System.debug('BEFORE: Total=' + o.TotalAmount + ' Tax=' + o.TotalTaxAmount + ' Grand=' + o.GrandTotalAmount + ' Override=' + o.TotalAmountOverride);

Order u = new Order(Id=o.Id, Description='Touched ' + String.valueOf(System.now()));
update u;

Order after = [SELECT Id, TotalAmount, TotalTaxAmount, GrandTotalAmount, TotalAmountOverride FROM Order WHERE Id = '801aj00002fQbT7AAK'];
System.debug('AFTER : Total=' + after.TotalAmount + ' Tax=' + after.TotalTaxAmount + ' Grand=' + after.GrandTotalAmount + ' Override=' + after.TotalAmountOverride);
