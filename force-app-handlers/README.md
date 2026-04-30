# Handlers

Apex classes that **handle inbound external events** — webhooks, REST callbacks, platform event listeners, and Apex trigger frameworks.

Handlers are the **boundary layer** between external systems and the Salesforce data model. They:
- Receive raw payloads (JSON from webhooks, sObjects from triggers)
- Validate, parse, and transform the input
- Delegate to Service classes for actual business logic
- Publish Platform Events when needed (e.g., for Guest User → automated user indirection)

## Classes in this directory

### REST / Webhook handlers

| Class | Type | Endpoint |
|---|---|---|
| `DocuSignConnectWebhook` | `@RestResource` | `/services/apexrest/docusign/webhook` (DocuSign Connect callback) |

### Trigger framework — Kevin O'Hara

| Class | Role |
|---|---|
| `TriggerHandler` | Base virtual class — Kevin O'Hara framework, MIT licensed (adapted from [github.com/kevinohara80/sfdc-trigger-framework](https://github.com/kevinohara80/sfdc-trigger-framework)). Provides `before/after insert/update/delete/undelete` hooks, recursion control via `setMaxLoopCount(n)`, bypass mechanism via `TriggerHandler.bypass('HandlerName')` |
| `DocuSignStatusUpdateTriggerHandler` | Maps DocuSign envelope status → `Contract.Status` (Platform Event handler) |
| `OrderItemTriggerHandler` | Auto-populates `OrderItem.Description` from `Product2.Name` (before insert/update) |
| `QuoteLineItemTriggerHandler` | Auto-populates `QuoteLineItem.Description` from `Product2.Name` (before insert/update) |

### Thin trigger pattern

All triggers in `force-app/main/default/triggers/` follow the **one-line thin trigger** convention:

```apex
trigger OrderItemAutoDescription on OrderItem (before insert, before update) {
    new OrderItemTriggerHandler().run();
}
```

Logic lives in the handler class (in this directory). The trigger itself is a routing shim only.

### Adding a new trigger

1. Create `force-app/main/default/triggers/MyObjectTrigger.trigger` with one line: `new MyObjectTriggerHandler().run();`
2. Create `MyObjectTriggerHandler.cls` here that `extends TriggerHandler`
3. Override the relevant context method(s): `beforeInsert()`, `afterUpdate()`, etc.
4. Access trigger records via `(List<MyObject>) Trigger.new` or via a typed wrapper getter

### Bypass mechanism

To temporarily disable a handler (useful in data migration scripts, batch jobs, or tests):

```apex
TriggerHandler.bypass('OrderItemTriggerHandler');
// ... do bulk DML without firing the handler ...
TriggerHandler.clearBypass('OrderItemTriggerHandler');
```

## Conventions

- Class name should end with `Webhook`, `Handler`, or `Listener`
- Webhook classes (`@RestResource`) should ALWAYS publish a Platform Event for downstream processing — Guest User context cannot directly update sObjects on managed/standard objects
- Triggers go in their own `triggers/` directory at metadata root, but their handlers (extending `TriggerHandler` framework like Kevin O'Hara's) live here
- Keep handler methods **thin** — heavy lifting belongs in Services

## Future additions

When more triggers are added, plan to introduce:
- `TriggerHandler.cls` (Kevin O'Hara framework, abstract base)
- One `*TriggerHandler.cls` per sObject (e.g., `InvoiceTriggerHandler.cls`, `ContractTriggerHandler.cls`)
