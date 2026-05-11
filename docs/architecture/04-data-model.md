# 04 — Data Model (ERD)

## Purpose

Shows the **sObject relationships** that carry data through the Quote-to-Cash lifecycle, plus the Custom Settings, Custom Metadata, and Platform Events that the integration layer depends on. Standard relationships use Salesforce default cardinality; custom fields highlighted with the integration system they bind to.

Useful for: explaining the data flow to a new engineer, scoping migrations, validating schema changes against downstream impact.

## Core lifecycle ERD

```mermaid
erDiagram
    Account ||--o{ Opportunity : "1:N (sales pipeline)"
    Account ||--o| Contact : "BillToContactId<br/>(primary contact)"
    Account ||--o{ Order : "1:N (purchase history)"
    Account ||--o{ Contract : "1:N (signed agreements)"
    Account ||--o{ Asset : "1:N (active products)"

    Opportunity ||--|| Quote : "Quote.OpportunityId<br/>(1:1 in this demo)"
    Quote ||--o{ QuoteLineItem : "1:N (configured items)"
    Quote ||--|| Order : "OrderItem populated<br/>via Convert action"

    Order ||--o{ OrderItem : "1:N (line items)"
    Order ||--o| Contract : "ContractId<br/>(generated on activate)"

    Contract ||--o{ Asset : "createOrUpdateAssetFromOrder<br/>invocable on Activate"
    Asset ||--o{ AssetLineItem : "1:N (per OrderItem)"

    QuoteLineItem }o--|| Product2 : "Product2Id"
    OrderItem }o--|| Product2 : "Product2Id"
    AssetLineItem }o--|| Product2 : "Product2Id"
    QuoteLineItem }o--|| PricebookEntry : "PricebookEntryId<br/>(Pricebook2Id match)"
    OrderItem }o--|| PricebookEntry : "PricebookEntryId"
    PricebookEntry }o--|| Pricebook2 : "Pricebook2Id<br/>(Standard or Custom)"
    PricebookEntry }o--|| Product2 : "Product2Id"

    Account {
        Id Id PK
        String Name
        Integer NumberOfEmployees "drives Product Qualification"
        String Industry "DACH segmentation"
        String BillingCountry "DE / AT / CH"
        Id BillToContactId FK "→ Contact"
    }

    Quote {
        Id Id PK
        Id OpportunityId FK
        Id AccountId FK
        Id BillToContactId FK
        Decimal TotalPrice "rollup"
        Decimal Total_Tax__c "rollup of QLI Tax_Amount"
        Decimal Total_With_VAT__c "formula: TotalPrice + Total_Tax__c"
        Status Status "Draft / Approved"
        Date ExpirationDate
    }

    QuoteLineItem {
        Id Id PK
        Id QuoteId FK
        Id Product2Id FK
        Id PricebookEntryId FK
        Decimal UnitPrice "modified by AttributePricingHandler"
        Decimal Quantity
        String Configured_RAM__c "16/32/64/128 GB"
        String Configured_SSD__c "256GB/512GB/1TB/2TB"
        String Configured_GPU__c "None/Workgroup/Pro/Workstation"
        Decimal Configured_Price_Adjustment__c "idempotency guard"
        Number Tax_Rate__c "formula: 0.19 (19% VAT)"
        Decimal Tax_Amount__c "formula: UnitPrice * Quantity * Tax_Rate"
    }

    Order {
        Id Id PK
        Id AccountId FK
        Id ContractId FK
        Status Status "Draft / Activated / Paid"
        Decimal TotalAmount
        String Jira_Ticket__c "TS-1, TS-2... (Apex callout)"
        String Stripe_Payment_Intent_Id__c "Mule webhook idempotency"
        String DocuSign_Envelope_Id__c "Apex DocuSignSendService"
        String Inventory_Status__c "In Stock / Out of Stock"
        Id Inventory_Approved_By__c FK "→ User (audit)"
        DateTime Inventory_Approved_At__c "audit timestamp"
        String Product_Type__c "Physical / Digital / Mixed (Choice router)"
        String License_Key__c "Digital fulfillment path"
    }

    Contract {
        Id Id PK
        Id AccountId FK
        Id OrderId__c FK "custom back-reference"
        Status Status "Draft → In Review → Approved → Awaiting Sig → Signed → Activated"
        String DocuSign_Envelope_Id__c "webhook correlation key"
        Date StartDate
        Date EndDate
        Integer ContractTerm "months"
        Id Manager_Profile__c FK "→ User (approver)"
    }

    Asset {
        Id Id PK
        Id AccountId FK
        Id ContractId FK
        Id Product2Id FK
        Status Status "Active / Inactive"
        Decimal Price
    }

    Product2 {
        Id Id PK
        String Name
        String ProductCode
        String Family "Workstations / Peripherals / etc"
        Boolean IsActive
        String Type "MUST be NULL (gotcha)"
        Id BasedOnId FK "→ ProductClassification"
        ConfigureDuringSale ConfigureDuringSale "Allowed"
    }
```

## Integration support objects

```mermaid
erDiagram
    Notion_Config__c {
        Id Id PK
        Text Token__c "Bearer token"
        Text Parent_Page_Id__c "Notion page UUID"
    }
    Jira_Config__c {
        Id Id PK
        URL Base_URL__c "https://*.atlassian.net"
        Text Auth_Token__c "base64(email:token)"
        Text Project_Key__c "TS"
        Text Default_Issue_Type__c "Task"
    }
    DocuSign_Config__c {
        Id Id PK
        Text Account_Id__c "DocuSign API account UUID"
        URL Base_URL__c "demo.docusign.net / account-d.docusign.com"
        Text HMAC_Secret__c "webhook signature key"
    }
    Inventory_Check_Requested__e {
        Id OrderId__c "Platform Event field"
        String AccountName__c
        Decimal TotalAmount__c
        URL ApprovalUrl__c "deep link to VF page"
    }
    DocuSign_Signed__e {
        String Envelope_Id__c "Platform Event field"
        String Envelope_Status__c "Completed / Declined"
        DateTime Signed_At__c
    }
    Techno_Attribute_Price_Rule__mdt {
        Id MasterLabel PK
        Id Product2_Id__c "lookup-by-ID composite key"
        String Attribute_Name__c "RAM / SSD / GPU"
        String Attribute_Value__c "32GB / 1TB / Pro"
        Decimal Price_Adjustment__c "€200 / €150 / €400"
    }
```

## Standard objects + custom fields per integration

| sObject | Custom field | Bound to | Populated by |
|---------|--------------|----------|--------------|
| `QuoteLineItem` | `Tax_Rate__c`, `Tax_Amount__c` | DACH VAT (19%) | Formula (no Apex) |
| `QuoteLineItem` | `Configured_RAM__c`, `Configured_SSD__c`, `Configured_GPU__c` | Bundle configurator | UI selection |
| `QuoteLineItem` | `Configured_Price_Adjustment__c` | AttributePricingHandler idempotency | `@future` Apex |
| `Quote` | `Total_Tax__c` | DACH VAT rollup | Rollup Summary |
| `Quote` | `Total_With_VAT__c` | Quote PDF display | Formula |
| `Order` | `Jira_Ticket__c` | JIRA REST API | `JiraTicketService.createForOrder()` |
| `Order` | `Stripe_Payment_Intent_Id__c` | Stripe webhook idempotency | Mule SF Connector |
| `Order` | `DocuSign_Envelope_Id__c` | DocuSign envelope correlation | `DocuSignSendForSignatureService` |
| `Order` | `Inventory_Status__c`, `Inventory_Approved_By/At__c` | Warehouse VF page audit | `WarehouseInventoryApprovalController` |
| `Order` | `Product_Type__c` | Mule Choice router | Apex trigger on OrderItem insert |
| `Order` | `License_Key__c` | Digital fulfillment | Mule UUID generator |
| `Contract` | `DocuSign_Envelope_Id__c` | DocuSign webhook correlation | `DocuSignSendForSignatureService` |
| `Contract` | `Manager_Profile__c` | Approval Process routing | Manual lookup |

## Cardinality + delete behavior

- **Account → Opportunity / Order / Contract / Asset**: 1:N, default cascade. Deleting Account purges all children — by design, since these records have no value without parent context.
- **Opportunity → Quote**: nominally 1:N but in this demo 1:1 (one Quote per Opp). Quote.OpportunityId is a Master-Detail-like reference (deleteConstraint=SetNull would orphan revenue data).
- **Quote → Order**: created via `Convert to Order` Lightning action. Quote remains for historical reference.
- **Order → Contract**: 1:0..1. Order may exist without Contract (immediate fulfillment scenarios). Contract always references back via `OrderId__c` custom field.
- **Contract → Asset**: 1:N via `createOrUpdateAssetFromOrder` invocable. Asset persists even if Contract is renewed.
- **Custom Setting deletions** are blocked at platform level for Protected Hierarchy Custom Settings to prevent accidental credential wipes.

## Key data model observations

1. **Product2.Type=NULL is a hard-coded constraint** — not enforced by platform but required for Browse Catalog visibility (entry 8 in Notion portfolio). The field is read-only after insert; fixing requires record recreation.
2. **PricebookEntry is the catalog membership gate** — even with RLM PricingProcedure, products without active PricebookEntry on the Standard Pricebook are invisible to Quote line item lookup.
3. **Custom Metadata over Custom Settings** for `Techno_Attribute_Price_Rule__mdt` because mdt is deployable via SFDX (version-controlled) and has no governor cost on `getAll()`. Custom Settings reserved for credentials (Protected Hierarchy avoids accidental record exposure).
4. **Platform Events have no FK relationships** — they're message-bus records, not persisted state. `Inventory_Check_Requested__e` carries OrderId as text, not as a true Salesforce Id lookup, because Mule subscribers don't have FLS context.
5. **The integration correlation pattern** uses external IDs stored on Order/Contract: `Stripe_Payment_Intent_Id__c`, `DocuSign_Envelope_Id__c`, `Jira_Ticket__c`. Inbound webhooks query by these fields rather than internal Salesforce Ids, since external systems only know the external Id.

## Drill-down

For the deployment pipeline that pushes this schema into a Salesforce org, see [05 — CI/CD Pipeline](05-cicd.md).
