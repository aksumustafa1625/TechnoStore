// Test the new OrderTriggerHandler — verify BillToContactId / ShipToContactId
// and Billing/Shipping addresses auto-populate from Account when missing.

// Use the Elbe (Hamburg) account for the test
Account elbe = [SELECT Id, Name FROM Account WHERE Name = 'Elbe Technology Distribution GmbH' LIMIT 1];

// Find its first Contact (should be Klaus Hoffmann)
Contact c = [SELECT Id, Name FROM Contact WHERE AccountId = :elbe.Id ORDER BY CreatedDate ASC LIMIT 1];
System.debug('Expected primary contact: ' + c.Name + ' (' + c.Id + ')');

// Create a minimal Order — only AccountId + Status + EffectiveDate (the required fields)
// Leave BillToContactId / ShipToContactId / addresses BLANK on purpose
Order o = new Order(
    AccountId     = elbe.Id,
    Status        = 'Draft',
    EffectiveDate = Date.today(),
    Name          = '⚡ Trigger Test — leave blanks'
);

System.debug('BEFORE INSERT: BillToContactId=' + o.BillToContactId + ', BillingCity=' + o.BillingCity);

insert o;

// Re-query the just-inserted order to see what the trigger populated
Order created = [
    SELECT Id, Name, BillToContactId, BillToContact.Name, ShipToContactId, ShipToContact.Name,
           BillingStreet, BillingCity, BillingPostalCode, BillingCountry,
           ShippingStreet, ShippingCity, ShippingPostalCode, ShippingCountry
    FROM Order WHERE Id = :o.Id
];

System.debug('===== AFTER INSERT (post-trigger) =====');
System.debug('BillToContact:  ' + (created.BillToContact != null ? created.BillToContact.Name : 'NULL ⚠️'));
System.debug('ShipToContact:  ' + (created.ShipToContact != null ? created.ShipToContact.Name : 'NULL ⚠️'));
System.debug('Billing:        ' + created.BillingStreet + ', ' + created.BillingCity + ', '
                                + created.BillingPostalCode + ', ' + created.BillingCountry);
System.debug('Shipping:       ' + created.ShippingStreet + ', ' + created.ShippingCity + ', '
                                + created.ShippingPostalCode + ', ' + created.ShippingCountry);

if (created.BillToContactId != null && created.BillToContactId == c.Id) {
    System.debug('✅ Trigger PASSED — BillToContact auto-populated correctly');
} else {
    System.debug('❌ Trigger FAILED — BillToContact NOT populated');
}

// Cleanup — delete the test order
delete created;
System.debug('Test order cleaned up');
