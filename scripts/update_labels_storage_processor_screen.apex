// COSMETIC ONLY — updates AttributePicklistValue Name + DisplayValue with " (+$X)" suffix.
// Does NOT change actual pricing. Demo user will pick base values; the price differentials
// are visible in the dropdown but not applied at the backend (no AttributeBasedAdjustment
// records created for these — only RAM has real attribute pricing).
//
// Value field stays at original (used by trigger matching for RAM, ignored by these others).

List<AttributePicklistValue> updates = new List<AttributePicklistValue>{
    // Storage
    new AttributePicklistValue(Id='0v6aj000000G24iAAC', Name='SSD Hard Drive 512GB (+$100)', DisplayValue='SSD Hard Drive 512GB (+$100)'),
    new AttributePicklistValue(Id='0v6aj000000G24gAAC', Name='SSD Hard Drive 1TB (+$200)',   DisplayValue='SSD Hard Drive 1TB (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24jAAC', Name='SSD Hard Drive 2TB (+$400)',   DisplayValue='SSD Hard Drive 2TB (+$400)'),
    new AttributePicklistValue(Id='0v6aj000000G24fAAC', Name='Cloud Storage 2TB (+$300)',    DisplayValue='Cloud Storage 2TB (+$300)'),
    new AttributePicklistValue(Id='0v6aj000000G24kAAC', Name='Cloud Storage 6TB (+$600)',    DisplayValue='Cloud Storage 6TB (+$600)'),

    // Processor
    new AttributePicklistValue(Id='0v6aj000000G24cAAC', Name='i7-CPU 4.7GHz (+$200)',         DisplayValue='i7-CPU 4.7GHz (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24dAAC', Name='Intel Core i9 5.2 GHz (+$500)', DisplayValue='Intel Core i9 5.2 GHz (+$500)'),

    // Screen Size
    new AttributePicklistValue(Id='0v6aj000000G24RAAS', Name='15 Inch (+$100)',               DisplayValue='15 Inch (+$100)'),
    new AttributePicklistValue(Id='0v6aj000000G24QAAS', Name='24 Inch (+$200)',               DisplayValue='24 Inch (+$200)'),
    new AttributePicklistValue(Id='0v6aj000000G24OAAS', Name='27 Inch (+$300)',               DisplayValue='27 Inch (+$300)')
};
update updates;
System.debug('Updated ' + updates.size() + ' picklist labels');

// Verify
for (AttributePicklistValue v : [SELECT DisplayValue, Value FROM AttributePicklistValue WHERE Id IN :new Map<Id, AttributePicklistValue>(updates).keySet() ORDER BY DisplayValue]) {
    System.debug('Display="' + v.DisplayValue + '" | Value="' + v.Value + '" (Value used for matching, unchanged)');
}
