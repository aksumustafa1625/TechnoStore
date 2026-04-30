# Actions

Apex classes that expose `@InvocableMethod` operations consumable by **Agentforce / Einstein Copilot agents** and **declarative tools** (Flow, Process Builder).

These differ from Services in that they're designed for **AI agent consumption** — heavy use of `@InvocableVariable(label='...' description='...')` so the LLM understands when and how to call them.

## Classes in this directory

| Class | Purpose | Consumer |
|---|---|---|
| `GetRevenueSummaryAction` | Returns aggregated revenue metrics for the dashboard / agent answers | Agentforce agent's "What was last week's revenue?" prompt |
| `SendPaymentRemindersAction` | Triggers reminder emails to customers with unpaid invoices > N days old | Agentforce agent's "Remind everyone with overdue invoices" prompt |

## Conventions

- Class name must end with `Action`
- The single `@InvocableMethod` declares verbose `label` and `description` for the agent UI
- Inputs use `@InvocableVariable` with descriptive labels (these become the agent's slot questions)
- Outputs use `@InvocableVariable` on a returned wrapper class
- Wrapping logic: parse inputs → validate → delegate to a Service → return wrapped response
- Errors should return as part of the response wrapper (not throw) so the agent can surface them gracefully
