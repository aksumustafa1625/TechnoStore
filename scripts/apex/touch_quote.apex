Quote q = [SELECT Id, QuoteNumber, Subtotal, TotalPrice, Tax, GrandTotal FROM Quote WHERE QuoteNumber = '00000075' LIMIT 1];
System.debug('BEFORE: TotalPrice=' + q.TotalPrice + ' Tax=' + q.Tax + ' GrandTotal=' + q.GrandTotal);

// Trigger flow by updating
Quote u = new Quote(Id=q.Id, Description=q.QuoteNumber + ' ' + String.valueOf(System.now()));
update u;

Quote after = [SELECT Id, Subtotal, TotalPrice, Tax, GrandTotal FROM Quote WHERE Id=:q.Id];
System.debug('AFTER : TotalPrice=' + after.TotalPrice + ' Tax=' + after.Tax + ' GrandTotal=' + after.GrandTotal);
