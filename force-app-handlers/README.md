# Handlers

Apex classes that **handle inbound external events** — webhooks, REST callbacks, platform event listeners, and Apex trigger frameworks.

Handlers are the **boundary layer** between external systems and the Salesforce data model. They:
- Receive raw payloads (JSON from webhooks, sObjects from triggers)
- Validate, parse, and transform the input
- Delegate to Service classes for actual business logic
- Publish Platform Events when needed (e.g., for Guest User → automated user indirection)

## Classes in this directory

| Class | Type | Endpoint / Trigger |
|---|---|---|
| `DocuSignConnectWebhook` | `@RestResource` | `/services/apexrest/docusign/webhook` (DocuSign Connect callback) |

## Conventions

- Class name should end with `Webhook`, `Handler`, or `Listener`
- Webhook classes (`@RestResource`) should ALWAYS publish a Platform Event for downstream processing — Guest User context cannot directly update sObjects on managed/standard objects
- Triggers go in their own `triggers/` directory at metadata root, but their handlers (extending `TriggerHandler` framework like Kevin O'Hara's) live here
- Keep handler methods **thin** — heavy lifting belongs in Services

## Future additions

When more triggers are added, plan to introduce:
- `TriggerHandler.cls` (Kevin O'Hara framework, abstract base)
- One `*TriggerHandler.cls` per sObject (e.g., `InvoiceTriggerHandler.cls`, `ContractTriggerHandler.cls`)
