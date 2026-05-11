# ADR-005: Kevin O'Hara TriggerHandler Framework Adoption

## Status

**Accepted**

## Date

2026-04-30

## Author

Mustafa Aksu

## Context

Salesforce trigger anti-patterns are well-documented in the developer community: one giant trigger file mixing all sObject lifecycle events, business logic inline in trigger context, no recursion guard, no test-isolation discipline, no ordering between handlers. Even small projects accumulate this debt quickly — and TechnoStore is not small.

The project has trigger logic on at least four sObjects:

- **Order** — afterUpdate fans out to JIRA + Slack + DocuSign + Stripe + branded email (5 downstream systems)
- **QuoteLineItem** — afterInsert + afterUpdate fires `AttributePricingHandler` `@future` for bundle pricing
- **Contract** — afterInsert auto-generates branded PDF + attaches as ContentVersion
- **OrderItem** — afterInsert recalculates `Order.Product_Type__c` (Physical / Digital / Mixed) for the Mule Choice router

Without a structured framework, four problems compound:

1. **Recursion** — `OrderTriggerHandler.afterUpdate()` fires DocuSign send, which receives a webhook, which updates `Contract.Status`, which is on `Contract` not `Order` so no infinite loop here — but the same pattern with `Order.Inventory_Status__c` updates absolutely would recurse. Hand-rolling recursion guards in every trigger is error-prone.
2. **Ordering ambiguity** — when 5 downstream handlers run on the same trigger event, which runs first is undefined. Tests pass intermittently because they assume an ordering that isn't enforced.
3. **Test-isolation difficulty** — handler logic embedded directly in trigger body cannot be unit-tested without a full DML scaffold (insert Order → trigger fires → assert side effects). Unit-testing the JIRA ticket creation handler in isolation requires a mocking framework or a way to invoke the handler method directly with a synthetic input.
4. **Bypass flexibility** — emergency disable of one handler during bulk data migration (e.g., `TriggerHandler.bypass('OrderTriggerHandler')` before inserting 50,000 historical Orders) requires either code deployment or hand-rolling a feature flag check at the top of every trigger.

Kevin O'Hara's [`sfdc-trigger-framework`](https://github.com/kevinohara80/sfdc-trigger-framework) is the **de-facto Salesforce community standard** for trigger architecture. It is MIT-licensed (compatible with TechnoStore's MIT license), well-maintained, widely-used in production at scale, and instantly recognizable to senior Salesforce engineers reviewing the codebase.

## Decision

Adopt the Kevin O'Hara `TriggerHandler` framework as the **non-negotiable trigger architecture standard** for TechnoStore.

Every Apex trigger in the project must:

1. **Be a 3-line file** that instantiates the corresponding handler class and calls `.run()`:
   ```apex
   trigger OrderTrigger on Order (before insert, before update, after insert, after update) {
       new OrderTriggerHandler().run();
   }
   ```
2. **Delegate to a handler class extending `TriggerHandler`** with explicit `beforeInsert()`, `afterUpdate()`, etc. method overrides.
3. **Keep business logic in private `@TestVisible` helper methods** within the handler, so unit tests can call them with mocked Lists without DML scaffolding.

`TriggerHandler.cls` is **vendored verbatim** from the upstream repository with only the API version updated. It is NEVER edited locally — upstream improvements can be pulled by replacing the file.

The framework's `bypass()` / `clearBypass()` static methods are used during data migration scripts to temporarily disable specific handlers:

```apex
TriggerHandler.bypass('OrderTriggerHandler');  // disable for bulk insert
insert hugeListOfHistoricalOrders;
TriggerHandler.clearBypass('OrderTriggerHandler');
```

`setMaxLoopCount(N)` configures recursion protection — set to `3` for TechnoStore handlers to allow legitimate cascade DML (e.g., DocuSign webhook → Contract.Status update → ContractTriggerHandler fires again to regenerate the PDF) while preventing infinite loops.

## Consequences

### Positive

- **Free recursion guard** — the framework's static `loopCountMap` short-circuits handlers exceeding `maxLoopCount`. No hand-rolled per-handler recursion bookkeeping.
- **Free bypass API** — `TriggerHandler.bypass('OrderTriggerHandler')` is one line in a data-migration script. Enables emergency disable without code deployment.
- **Test-isolation pattern via `@TestVisible`** — unit tests call `OrderTriggerHandler.handleJiraTicketCreation(mockList)` directly without inserting Orders. ~10x faster test execution and no DML governor consumption.
- **Community-standard recognizable pattern** — recruiters and code reviewers instantly identify it as production-grade Salesforce. The mere presence of `TriggerHandler.cls` is a credibility signal.
- **Clear ordering** — within `afterUpdate()`, handler method invocations are sequential and explicit in source code. No "Order Apex Class Order" Setup UI gymnastics.
- **Trigger file is 3 lines** — pull requests touching a trigger get 3 lines of diff; the heavy lifting happens in the handler class which is its own diff.

### Negative / Trade-offs

- **~50 lines of framework boilerplate** per Apex trigger (instantiation + handler class with overrides). For trivial triggers with one-line logic, this is overhead. Mitigated by: TechnoStore has no trivial triggers — every trigger fans out to multiple downstream actions.
- **Recursion guard is silent** — when the loop counter exceeds `maxLoopCount`, the handler is short-circuited without exception. A developer expecting the handler to fire may be confused. Mitigated by `System.debug` logging on bypass and explicit documentation in `CONTRIBUTING.md`.
- **Vendored code requires upstream tracking** — if Kevin O'Hara publishes a security fix to `TriggerHandler.cls`, we manually pull the update. The `LICENSE` file explicitly cites the upstream repo to make this clear.
- **`@TestVisible` private methods leak slightly into the test surface** — a test class can call methods that should be private. Mitigated by naming convention (`handleXxx` methods are by convention private-but-test-accessible).

## Alternatives Considered

### Alternative A — Inline trigger logic (anti-pattern)

Rejected because:
- Recursion, ordering, test-isolation, bypass — all four problems hit the project within weeks.
- Code reviewers and recruiters immediately flag inline-trigger-logic as junior/learner work.

### Alternative B — FFLib Apex Common (`fflib-apex-common`)

Considered as a richer enterprise pattern. Rejected for now because:
- FFLib bundles Service Layer, Unit of Work, Selector, Domain — a full multi-layer enterprise framework, not just trigger handling. The scope is much larger than what TechnoStore needs from a trigger framework specifically.
- FFLib's learning curve is significant (Apex Trigger Actions, Domain Layer, fflib_SObjectDomain) and would slow demo iteration.
- The Selector pattern from FFLib is adopted *separately* in TechnoStore (`force-app-services/` services delegate SOQL to per-sObject Selectors), without taking on the full FFLib framework. Best-of-both-worlds compromise.

Re-evaluate in a v2.0 production hardening phase.

### Alternative C — Salesforce Apex Trigger Framework (DX-template default)

Rejected because:
- The DX-template default produces an empty `force-app/main/default/triggers/` folder with no framework. There's no opinionated default; you build your own or pick from the community.
- Building our own framework from scratch is 4-6 hours of work that Kevin O'Hara has already done better.

### Alternative D — Apex Trigger Actions (custom-metadata-driven framework)

Considered. Rejected for now because:
- Adds Custom Metadata Type configuration on top of code — every new trigger handler is two files (Apex class + Trigger_Action__mdt record).
- Useful when multiple teams contribute handlers across the same trigger and need declarative ordering. TechnoStore is a solo project — no multi-team ordering coordination needed.
- The bypass mechanism is more elaborate in Trigger Actions but Kevin O'Hara's `bypass()` is sufficient for our scenarios.

## Migration notes

When converting an existing inline-trigger to the Kevin O'Hara pattern:

1. Copy `TriggerHandler.cls` + `TriggerHandler.cls-meta.xml` from the upstream repo into `force-app-handlers/main/default/classes/`. Preserve the MIT copyright header.
2. Create `<SObject>TriggerHandler.cls` extending `TriggerHandler`. Override the relevant `before*`/`after*` methods.
3. Move trigger body logic into private `@TestVisible` methods on the handler.
4. Replace trigger body with `new <SObject>TriggerHandler().run();`.
5. Update test classes to call handler methods directly via `@TestVisible` injection where possible (eliminate DML scaffolding for unit tests).
6. Set `maxLoopCount = 3` per handler (or appropriate value based on legitimate cascade depth).

The TechnoStore migration covered four sObjects in ~3 hours total.

## References

- **Memory**: `enterprise_apex_layout.md`
- **Notion portfolio entries**: 19 (Order Activation Trigger Architecture), 43 (Apex Code Organization — Kevin O'Hara TriggerHandler Framework Adoption)
- **Code**: `force-app-handlers/main/default/classes/TriggerHandler.cls`, `OrderTriggerHandler.cls`, `QuoteLineItemTriggerHandler.cls`, `ContractTriggerHandler.cls`
- **License attribution**: `LICENSE` (third-party section credits Kevin O'Hara)
- **Upstream**: [github.com/kevinohara80/sfdc-trigger-framework](https://github.com/kevinohara80/sfdc-trigger-framework) (MIT)
- **Related ADRs**: ADR-004 (six-package layout — TriggerHandler lives in `force-app-handlers/`)
