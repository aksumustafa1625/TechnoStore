# 03 — Quote-to-Cash Sequence Diagram

## Purpose

Shows the complete **Quote-to-Cash lifecycle** as a time-ordered sequence of messages between actors and systems. Each arrow is a real HTTP call, DML, or webhook delivery. Latency numbers reflect measured performance in the production demo recording (2026-05-01).

This is **the diagram recruiters ask about in interviews**. Print it before the call.

## Diagram — Part 1: Quote → Order activation → Payment

```mermaid
sequenceDiagram
    autonumber

    actor Rep as Sales Rep
    actor Cust as B2B Customer
    participant SF as Salesforce<br/>(TechnoStore Org)
    participant APH as AttributePricing<br/>Handler (@future)
    participant Mule as MuleSoft<br/>Anypoint
    participant Stripe as Stripe API
    participant DS as DocuSign API
    participant JIRA as JIRA Cloud
    participant Slack as Slack<br/>(#warehouse + #payments)

    %% ============ Quote stage ============
    Rep->>SF: Open Browse Catalog (Hamburg DataWorks context)
    SF->>SF: Product Qualification filter:<br/>4 workstation tiers visible
    SF-->>Rep: Render tiers (Entry / Standard / Pro / MC)

    Rep->>SF: Select Workstation Pro + Configure (RAM=32GB)
    SF->>SF: Save QuoteLineItem
    SF-)APH: @future invocation (async)
    APH->>SF: Query Techno_Attribute_Price_Rule__mdt
    APH->>SF: UPDATE QuoteLineItem.UnitPrice += €200
    Note over APH,SF: 2-5 sec async settling

    SF->>SF: Quote formula recalc:<br/>Total_Tax__c, Total_With_VAT__c
    SF-->>Rep: Quote PDF (orange branded)

    %% ============ Order activation fan-out ============
    Rep->>SF: Convert Quote → Order, click Activate
    SF->>SF: Order.Status: Draft → Activated
    Note over SF: OrderTriggerHandler.afterUpdate()<br/>detects Status transition

    par Cross-system fan-out (5 sec total)
        SF->>JIRA: POST /rest/api/3/issue (Apex callout, Basic Auth)
        JIRA-->>SF: 201 Created — issue key TS-N
        SF->>SF: UPDATE Order.Jira_Ticket__c = 'TS-N'
    and
        SF-)SF: EventBus.publish(Inventory_Check_Requested__e)
        SF-)Mule: Streaming channel /event/...
        Mule->>Slack: POST #warehouse webhook<br/>Block Kit + deep link
    and
        SF->>DS: POST /v2.1/accounts/{id}/envelopes<br/>(Apex + Named Credential)
        DS-->>SF: 201 Created — envelopeId
        SF->>SF: UPDATE Contract.DocuSign_Envelope_Id__c<br/>+ Status = Awaiting Signature
        DS->>Cust: Email signing request
    and
        SF->>Mule: HTTP POST /stripe/intent<br/>(Order payload)
        Mule->>Stripe: POST /v1/payment_intents<br/>(form-encoded, Basic Auth)
        Stripe-->>Mule: 200 — client_secret + hosted URL
        Mule-->>SF: Payment URL
        SF->>Cust: Email orange INVOICE PDF<br/>+ Pay Now button
    end

    %% ============ Customer pays ============
    Cust->>Stripe: Open Pay Now → enter card 4242 4242 4242 4242
    Stripe->>Stripe: Process payment + SCA / 3DS
    Stripe-->>Cust: Success page
```

## Diagram — Part 2: Payment webhook → Fulfillment → Contract signing → Asset

```mermaid
sequenceDiagram
    autonumber

    actor Cust as B2B Customer
    actor Wh as Warehouse User
    participant SF as Salesforce
    participant Mule as MuleSoft
    participant Stripe as Stripe API
    participant Sendcloud as Sendcloud v3
    participant DHL as DHL Carrier
    participant DS as DocuSign API
    participant Slack as Slack

    %% ============ Stripe webhook + payment confirmation ============
    Stripe-)Mule: POST /stripe/webhook<br/>payment_intent.succeeded<br/>X-Stripe-Signature header
    Mule->>Mule: HMAC-SHA256 verify<br/>+ 5-min timestamp freshness
    Mule->>Mule: Idempotency guard:<br/>query SF for Order.Status=Paid

    par Scatter-Gather fan-out (3 sec total)
        Mule->>SF: UPSERT Order.Status=Paid<br/>+ Stripe_Payment_Intent_Id__c
    and
        Mule->>Slack: POST #payments-team webhook<br/>"✅ Payment received"
    and
        Mule->>SF: Invoke EmailWithBrandedPdf<br/>(green RECEIPT PDF)
        SF->>Cust: Email green RECEIPT
    end

    Mule-->>Stripe: 200 OK

    %% ============ Mule Choice Router branching ============
    Mule->>Mule: Choice router on<br/>Order.Product_Type__c

    alt Physical Order (Workstation)
        Mule->>Sendcloud: POST /api/v3/orders<br/>bare-array + integration_id 577997
        Sendcloud-->>Mule: 201 Created — order ref
        Sendcloud->>DHL: Schedule parcel pickup
        DHL-->>Sendcloud: Tracking number
        Sendcloud-)Mule: Tracking webhook
        Mule->>SF: UPDATE Order.Tracking_Number__c
        SF->>Cust: Email shipping notification
    else Digital Order (Software License)
        Mule->>Mule: Generate UUID license key
        Mule->>SF: UPDATE Order.License_Key__c
        SF->>Cust: Email welcome + download link
    end

    %% ============ Warehouse approval (parallel branch) ============
    Wh->>Slack: Receive #warehouse notification
    Wh->>SF: Click deep link → /apex/WarehouseInventoryApproval
    Wh->>SF: Mark In Stock
    SF->>SF: UPDATE Order.Inventory_Status__c=In Stock<br/>+ Approved_By + Approved_At audit

    %% ============ Customer signs DocuSign ============
    Cust->>DS: Open signing email → sign on Anchor Tab
    DS-)SF: POST /docusign_webhook (SF Site)<br/>envelopeStatus=Completed
    SF->>SF: Verify X-DocuSign-Signature-1 HMAC
    Note over SF: Guest User profile<br/>cannot DML Contract.Status<br/>directly (FLS)
    SF-)SF: Guest User publishes DocuSign_Signed__e
    SF->>SF: Trigger subscriber runs in<br/>system context, bypasses Guest FLS
    SF->>SF: UPDATE Contract.Status = Signed<br/>(idempotent: skip if already Signed)

    %% ============ Activate + Asset creation ============
    Note over SF: Rep clicks Activate Contract<br/>(custom screen flow)
    SF->>SF: Activate_Contract screen flow<br/>→ Autolaunched subflow<br/>(Apex restriction workaround)
    SF->>SF: Invoke createOrUpdateAssetFromOrder
    SF->>SF: INSERT Asset linked to<br/>Account + Order
    SF-->>Cust: Asset visible on customer record
```

## Latency budget (measured end-to-end)

| Stage | Elapsed time | Bottleneck |
|-------|--------------|------------|
| Browse Catalog → Quote saved | <2 sec | Product Qualification SOQL |
| Quote → Order Activate | <1 sec | Sync DML |
| Cross-system fan-out (JIRA + Slack + DocuSign + Stripe + email) | 2-6 sec | DocuSign envelope creation (slowest) |
| Customer click Pay Now → Stripe payment confirmation | 30-90 sec | Customer action |
| Stripe webhook → SF Order=Paid + RECEIPT + Slack | 2-5 sec | HMAC verify + Scatter-Gather |
| Mule Choice Router → Sendcloud → DHL pickup scheduled | 3-10 sec | Sendcloud carrier routing |
| DocuSign signed → Contract.Status=Signed | 30-60 sec | DocuSign Connect delivery |
| Activate Contract → Asset created | <5 sec | Sync subflow + DML |
| **Total Q2C lifecycle (excluding customer wait time)** | **~60 sec** | |

## Key sequence observations

1. **Order activation triggers a 4-way parallel fan-out** (par/and blocks in Mermaid) — JIRA + Slack + DocuSign + Stripe + email all kick off within 1 second of `OrderTriggerHandler.afterUpdate()` firing. Total elapsed = max(branch latencies), not sum.
2. **The Stripe webhook handler is the most security-critical step** — HMAC-SHA256 verification with 5-minute timestamp freshness window prevents replay attacks + spoofed payment events. Without this, any actor with the webhook URL could fake payments.
3. **Guest User + Platform Event indirection** for the DocuSign signed webhook bypasses Salesforce's Guest profile FLS restriction on `Contract.Status`. Guest publishes a Platform Event; the trigger subscriber runs in system context with full FLS.
4. **The Activate Contract screen flow → Autolaunched subflow indirection** exists because `createOrUpdateAssetFromOrder` is only invocable from Autolaunched flow context. Screen flow cannot call it directly.
5. **Idempotency guards** appear at two places — Stripe webhook handler skips if Order is already Paid (Stripe retries on 5xx); DocuSign trigger subscriber skips if Contract is already Signed (DocuSign retries on non-2xx).

## Drill-down

For the data structures these messages move through, see [04 — Data Model](04-data-model.md).
