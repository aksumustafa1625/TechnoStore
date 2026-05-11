# 01 — System Context Diagram (C4 Level 1)

## Purpose

Shows TechnoStore's place in the wider world: **who interacts with the system** and **what external systems it integrates with**. This is the highest-level architectural view — no internal Salesforce details, just the boundaries.

Useful for: onboarding stakeholders in 60 seconds, framing recruiter conversations, scoping new integration discussions.

## Diagram

```mermaid
graph TB
    %% ============ External Actors ============
    SalesRep(["👤 Sales Rep<br/><i>DACH-market sales team</i>"])
    Customer(["👤 B2B Customer<br/><i>Enterprise IT buyer<br/>Hamburg / Munich / Frankfurt / Cologne</i>"])
    Warehouse(["👤 Warehouse User<br/><i>Fulfillment operations</i>"])
    Finance(["👤 Finance Team<br/><i>Payment monitoring</i>"])
    Manager(["👤 Manager / Legal<br/><i>Contract approvers</i>"])

    %% ============ Central System ============
    TechnoStore["🏢 <b>TechnoStore</b><br/>Salesforce Revenue Cloud<br/>RLM + CLM + Industries CPQ"]

    %% ============ External Systems ============
    Stripe["💳 Stripe<br/><i>Hosted payment page<br/>+ webhook events</i>"]
    Sendcloud["📦 Sendcloud + DHL<br/><i>Parcel logistics<br/>v3 /orders API</i>"]
    DocuSign["✍️ DocuSign<br/><i>E-signature<br/>Connect webhooks</i>"]
    SlackPay["💬 Slack #payments-team<br/><i>Finance ops channel</i>"]
    SlackWh["💬 Slack #warehouse<br/><i>Operations channel</i>"]
    JIRA["🎫 Atlassian JIRA<br/><i>Fulfillment ticket tracking<br/>Agile sprint mgmt</i>"]
    Notion["📚 Notion<br/><i>50-entry STAR portfolio<br/>Programmatic publish</i>"]
    MuleSoft["🔌 MuleSoft Anypoint Studio<br/><i>Integration orchestration<br/>Choice router + Scatter-Gather</i>"]

    %% ============ Actor -> TechnoStore ============
    SalesRep -->|"configures Quote,<br/>activates Order"| TechnoStore
    Warehouse -->|"approves stock<br/>via custom VF page"| TechnoStore
    Manager -->|"approves Contract<br/>via screen flow"| TechnoStore
    Customer -->|"signs DocuSign,<br/>pays Stripe-hosted page"| TechnoStore

    %% ============ TechnoStore <-> MuleSoft (orchestration spine) ============
    TechnoStore <==>|"Platform Event channel<br/>+ HTTP outbound<br/>+ webhook callbacks"| MuleSoft

    %% ============ MuleSoft -> External (per Mule-vs-Apex matrix) ============
    MuleSoft -->|"PaymentIntent POST<br/>form-encoded"| Stripe
    Stripe -.->|"payment_intent.succeeded<br/>HMAC-signed webhook"| MuleSoft
    MuleSoft -->|"v3 /orders POST<br/>bare-array payload"| Sendcloud
    MuleSoft -->|"Block Kit notification"| SlackPay
    MuleSoft -->|"Block Kit notification<br/>+ deep link to VF page"| SlackWh

    %% ============ TechnoStore -> External direct (per Mule-vs-Apex matrix) ============
    TechnoStore -->|"envelope POST<br/>via Named Credential"| DocuSign
    DocuSign -.->|"signed event webhook<br/>→ SF Site Guest User<br/>→ Platform Event"| TechnoStore
    TechnoStore -->|"REST /rest/api/3/issue<br/>+ Agile /sprint API"| JIRA
    TechnoStore -->|"6-call multi-call orchestration<br/>nested-toggle pages"| Notion

    %% ============ Finance monitors Slack ============
    Finance -.->|"observes payment events"| SlackPay
    Warehouse -.->|"observes stock requests"| SlackWh

    %% ============ Styling ============
    style TechnoStore fill:#003F7F,stroke:#001E3D,color:#fff,stroke-width:3px
    style MuleSoft fill:#00A0DF,stroke:#006B96,color:#fff,stroke-width:2px
    style Stripe fill:#635BFF,stroke:#4A3FCF,color:#fff
    style Sendcloud fill:#28B463,stroke:#1D7E45,color:#fff
    style DocuSign fill:#FFCC22,stroke:#B89200,color:#000
    style SlackPay fill:#4A154B,stroke:#2D0C2E,color:#fff
    style SlackWh fill:#4A154B,stroke:#2D0C2E,color:#fff
    style JIRA fill:#0052CC,stroke:#003A91,color:#fff
    style Notion fill:#000,stroke:#333,color:#fff
```

## Reading the diagram

- **Solid arrows** (→) are synchronous outbound calls initiated by the actor or system on the left
- **Dashed arrows** (-.->) are asynchronous webhooks or event subscriptions initiated by the system on the right
- **Bold bidirectional** (⇔) marks the orchestration spine where Salesforce and MuleSoft cooperate as peers
- **Color coding** matches each external service's brand palette so the visual is instantly recognizable

## Key architectural observations

1. **TechnoStore Salesforce sits at the center** — every actor's interaction either reads from it (Sales Rep view) or writes to it via custom flow (Warehouse approval, Manager approval).
2. **MuleSoft is the orchestration spine for multi-system fan-out** — not a router for all integrations. Single-system Apex callouts (DocuSign, JIRA, Notion) bypass Mule per the Mule-vs-Apex decision matrix (see `entry 46` in the Notion portfolio).
3. **Webhook receivers (Stripe → Mule, DocuSign → SF Site) use HMAC signature verification** to prevent spoofing — non-negotiable for payment-affecting events.
4. **The Customer never directly touches Salesforce** — they interact with Stripe-hosted payment page + DocuSign signing UI + branded email PDFs. Salesforce sits behind the integration layer.

## Drill-down

For the next level of detail (what's *inside* TechnoStore Salesforce + what's inside MuleSoft), see [02 — Container Diagram](02-container.md).
