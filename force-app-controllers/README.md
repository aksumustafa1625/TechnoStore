# Controllers

Apex classes that serve as backends for **Lightning Web Components** and **Visualforce pages**.

These classes follow the **MVC controller** pattern:
- They expose `@AuraEnabled` methods to LWCs (or properties to VF pages).
- They orchestrate business logic by **delegating to Service classes** in `force-app-services`.
- They keep transactional integrity but contain **no domain logic**.

## Classes in this directory

| Class | Surface | Used by |
|---|---|---|
| `RevenuePulseController` | `@AuraEnabled(cacheable=true)` | `revenuePulse` LWC (Revenue Pulse tab) |
| `InvoicePdfController` | Visualforce backing class | `TechnoStoreBrandedInvoice.page`, `TechnoStoreInvoicePreviewPdf.page` |

## Conventions

- Class name must end with `Controller`
- Each public method should be either `@AuraEnabled` or expose a property/getter to a VF page
- Heavy SOQL or DML belongs in a Service class, not here
- Avoid `try/catch` that swallows errors — let them propagate to the UI for surfacing
