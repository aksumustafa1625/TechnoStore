// Verify Asset creation fires when Order.Status flips Draft → Activated.
// Test cycle: create Order, add OrderItem, activate, check Asset, cleanup.

System.debug('===== ASSET-ON-ACTIVATION TEST =====');

// Use Elbe account + Mustafa Aksu contact
Account elbe = [SELECT Id FROM Account WHERE Name = 'Elbe Technology Distribution GmbH' LIMIT 1];
Contact mustafa = [SELECT Id, Name FROM Contact WHERE AccountId = :elbe.Id LIMIT 1];

// Pick any product that has a PricebookEntry
PricebookEntry pbe = [SELECT Id, Product2Id, Product2.Name, UnitPrice
                       FROM PricebookEntry
                       WHERE IsActive = true AND Product2.IsActive = true
                       LIMIT 1];
System.debug('Test product: ' + pbe.Product2.Name + ' @ €' + pbe.UnitPrice);

// Standard pricebook
Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

// ============================================================
// Step 1: Create Draft Order
// ============================================================
Order o = new Order(
    AccountId     = elbe.Id,
    Status        = 'Draft',
    EffectiveDate = Date.today(),
    Pricebook2Id  = stdPbId,
    Name          = '⚡ Asset Trigger Test'
);
insert o;
System.debug('Created Order: ' + o.Id);
System.debug('  After beforeInsert trigger — BillToContactId: ' + [SELECT BillToContactId FROM Order WHERE Id = :o.Id].BillToContactId);

// Step 2: Add 1 OrderItem
OrderItem oi = new OrderItem(
    OrderId          = o.Id,
    PricebookEntryId = pbe.Id,
    Product2Id       = pbe.Product2Id,
    Quantity         = 1,
    UnitPrice        = pbe.UnitPrice
);
insert oi;
System.debug('Created OrderItem');

// Step 3: Activate Order — should trigger Asset creation
o.Status = 'Activated';
update o;
System.debug('Activated Order');

// Step 4: Verify Asset created (filter by Account + Product since Description isn't filterable)
List<Asset> assets = [
    SELECT Id, Name, AccountId, ContactId, Product2Id, Quantity, Price, Status, Description, PurchaseDate
    FROM Asset
    WHERE AccountId = :elbe.Id
    AND Product2Id = :pbe.Product2Id
    AND CreatedDate = TODAY
    ORDER BY CreatedDate DESC
    LIMIT 5
];

System.debug('===== ASSETS CREATED: ' + assets.size() + ' =====');
for (Asset a : assets) {
    System.debug('  ✅ ' + a.Name + ' [Status=' + a.Status + ', Qty=' + a.Quantity + ', Price=€' + a.Price + ', Date=' + a.PurchaseDate + ']');
}

if (assets.size() == 1) {
    System.debug('✅✅✅ TRIGGER PASSED — Asset auto-created on Order activation');
} else {
    System.debug('❌ TRIGGER FAILED — expected 1 Asset, got ' + assets.size());
}

// Cleanup
delete assets;
o.Status = 'Draft';
update o;
delete oi;
delete o;
System.debug('Test cleaned up');
