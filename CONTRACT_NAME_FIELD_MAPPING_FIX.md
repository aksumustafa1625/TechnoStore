# Contract Name Field Mapping Fix

## Problem
When creating a Contract from an Order, you received this error:
```
We couldn't complete your request because the source object field mapped to the Name field is null or has an empty value.
```

## Root Cause
The Contract standard object in Salesforce **does not have a Name field** - it uses `ContractNumber` (auto-generated) instead. However, the CLM (Contract Lifecycle Management) field mapping was trying to map `Order.Name` to a non-existent `Contract.Name` field.

## Solution Implemented
1. Created a custom field `Name__c` on the Contract object
2. This field will store the contract name from the Order

## Next Steps - MANUAL CONFIGURATION REQUIRED

After the field is deployed, you need to update the CLM field mapping in your Salesforce org:

### Option A: Update Field Mapping (Recommended)
1. Go to **Setup** → **Contract Lifecycle Management** → **Field Mappings**
2. Find the mapping from **Order** to **Contract**
3. Update the Name field mapping:
   - Change from: `Order.Name` → `Contract.Name` (invalid)
   - Change to: `Order.Name` → `Contract.Name__c` (custom field)
4. Save the mapping

### Option B: Remove Invalid Mapping
1. Go to **Setup** → **Contract Lifecycle Management** → **Field Mappings**
2. Find the mapping from **Order** to **Contract**
3. Remove the Name field mapping entirely (if not required)
4. Save the mapping

## Verification
After updating the mapping, test the Contract creation:
1. Navigate to an Order (e.g., Order 00000137 - "10 Computer Quote")
2. Try to create a Contract from the Order
3. The Contract should now be created successfully with the Name__c field populated

## Field Details
- **API Name**: `Name__c`
- **Label**: Contract Name
- **Type**: Text (255)
- **Purpose**: Store contract name from Order.Name during CLM contract creation

## Testing
Run this SOQL after creating a contract:
```sql
SELECT Id, ContractNumber, Name__c, AccountId, Account.Name 
FROM Contract 
ORDER BY CreatedDate DESC 
LIMIT 1
```

The `Name__c` field should contain the value from the Order's Name field (e.g., "10 Computer Quote").