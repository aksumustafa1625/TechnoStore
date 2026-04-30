# Services

Apex classes that contain **reusable business logic** invoked by Controllers, Flows (via Invocable methods), or other Apex code.

Services are the heart of the domain — they:
- Encapsulate transactions (create, update, delete records)
- Integrate with external systems (Stripe, DocuSign, Sendcloud)
- Compose multiple SObject operations into atomic units of work
- Are **stateless** and **idempotent** where possible

## Classes in this directory

| Class | Domain | Trigger |
|---|---|---|
| `AttachAndEmailInvoicePdf` | Invoice → PDF Receipt | Invocable from `Send_Invoice_Receipt_With_Pdf` flow (legacy, draft) |
| `AttachAndEmailInvoicePreview` | Invoice → Pre-payment branded mail + orange PDF | Invocable from `Send_Stripe_Payment_Email` flow |
| `EmailWithBrandedPdf` | Invoice → Notification mail (License/Shipping/Combined) + RECEIPT PDF | Invocable from `Send_Activation_Email`, `Send_Shipping_Notification`, `Send_Combined_Notification` flows |
| `DocuSignSendForSignatureService` | Contract → DocuSign envelope creation via REST | Invocable from `Send_Contract_Via_DocuSign` flow |

## Conventions

- Class name must end with `Service`
- Public methods are `@InvocableMethod` (callable from flows) or `public static`
- Services NEVER take or return Apex Pages / VF references — that's Controller territory
- Email/HTTP/PDF generation belongs here
- Always wrap external HTTP calls in try/catch that logs but does not throw if the rest of the chain should continue
