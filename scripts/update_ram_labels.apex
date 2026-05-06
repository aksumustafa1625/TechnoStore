// Picklist Label Manipulation: rename RAM values to include price differentials
// This is a clever low-risk demo hack — Configure UI dropdown auto-renders these labels.
// Backend behavior unchanged: trigger still applies AttributeBasedAdjustment based on the
// underlying value (RAM 16GB / 32GB / 64GB).

// Note: AttributeAdjustmentCondition uses StringValue='RAM 32GB' for matching.
// We'll keep Code/Value at the original 'RAM 32GB' so the trigger still matches.
// Only Name + DisplayValue (what user sees) change.

List<AttributePicklistValue> updates = new List<AttributePicklistValue>{
    new AttributePicklistValue(
        Id='0v6aj000000G24WAAS',  // RAM 16GB
        Name='RAM 16GB (+$100)',
        DisplayValue='RAM 16GB (+$100)'
    ),
    new AttributePicklistValue(
        Id='0v6aj000000G24UAAS',  // RAM 32GB
        Name='RAM 32GB (+$200)',
        DisplayValue='RAM 32GB (+$200)'
    ),
    new AttributePicklistValue(
        Id='0v6aj000000G24VAAS',  // RAM 64GB
        Name='RAM 64GB (+$400)',
        DisplayValue='RAM 64GB (+$400)'
    )
};
update updates;

System.debug('--- Updated picklist labels ---');
for (AttributePicklistValue v : [SELECT Id, Name, DisplayValue, Value FROM AttributePicklistValue WHERE Id IN ('0v6aj000000G24WAAS','0v6aj000000G24UAAS','0v6aj000000G24VAAS')]) {
    System.debug('Display: ' + v.DisplayValue + ' | Value (for trigger match): ' + v.Value);
}
