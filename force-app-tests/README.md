# Tests

Apex unit tests for **our custom classes** (controllers, services, handlers, actions).

This package directory is currently empty — a placeholder for future test classes. Tests for Salesforce-auto-generated classes (`ChangePasswordControllerTest`, `CommunitiesLoginControllerTest`, etc.) live in `force-app/main/default/classes/` next to the auth/community classes they test, because those classes are platform-managed and not ours.

## Why a separate `force-app-tests/` directory

Modeled after the Java / Maven convention:
```
src/main/java/      ← production code
src/test/java/      ← test code
```

Apex doesn't enforce this split, but doing it gives:
1. **Visibility** — at a glance, see how much of our codebase is tested
2. **Coverage discipline** — empty test directory is a visible smell that pushes the team to write tests
3. **CI/CD efficiency** — pipelines can selectively run "tests-only" deploys against scratch orgs for fast PR validation

## Co-locate vs separate folder — the trade-off

There are two camps in the Salesforce community:

| Approach | Example | Pros | Cons |
|---|---|---|---|
| **Co-locate** | `services/OrderService.cls` + `services/OrderServiceTest.cls` (same folder) | Easier to find tests for a class; refactor/delete moves both together; PR review shows class + test side-by-side | Mixing prod and test code blurs the dependency graph |
| **Separate folder** (this directory) | `services/OrderService.cls` + `tests/OrderServiceTest.cls` | Clean prod/test boundary; aligns with non-Apex enterprise conventions; selective deploys easier | Extra clicks to find a class's test; risk of orphaned tests |

For this project we adopt the **separate folder** approach.

## Test class conventions

When tests are added here:

- Mirror the source layout: `force-app-services/EmailWithBrandedPdf.cls` → `force-app-tests/EmailWithBrandedPdfTest.cls`
- One test class per production class (no shared "AllServicesTest")
- Cover positive + negative + boundary paths
- Use `@TestSetup` to share fixture data across test methods
- Use `Test.startTest()` / `Test.stopTest()` to enter async limit context for invocable methods that do callouts or DML in async
- Mock callouts with `Test.setMock(HttpCalloutMock.class, new MockClass())` for any HTTP-dependent classes (DocuSign send, Sendcloud, Stripe)
- Aim for 90%+ line coverage on critical services; Salesforce production deploy minimum is 75%

## Future structure

Once tests are added, this directory will look like:

```
force-app-tests/main/default/classes/
├── controllers/                          (logical grouping in naming, since SF flat namespace)
│   ├── RevenuePulseControllerTest.cls
│   ├── InvoicePdfControllerTest.cls
│   ├── CreateContractControllerTest.cls
│   └── UpdateContractControllerTest.cls
├── services/
│   ├── EmailWithBrandedPdfTest.cls
│   ├── DocuSignSendForSignatureServiceTest.cls
│   └── ...
├── handlers/
│   └── DocuSignConnectWebhookTest.cls
└── actions/
    ├── GetRevenueSummaryActionTest.cls
    └── SendPaymentRemindersActionTest.cls
```

(Note: Salesforce's flat namespace means all `*Test.cls` files live directly under `classes/`. The visual grouping above is illustrative — naming will keep them logically grouped via prefix/suffix.)

## Mock patterns to standardize on

When writing tests, use these mock patterns consistently:

- **HTTP callouts:** `HttpCalloutMock` interface for Stripe, DocuSign, Sendcloud, Slack
- **Email sending:** `Messaging.sendEmail` is automatically mocked in tests; assertions on `Messaging.sendEmail` calls available via `Limits.getEmailInvocations()`
- **PDF generation:** `Page.X.getContentAsPDF()` returns null in test context; check via `Test.isRunningTest()` and provide stub bytes
- **Platform Events:** `EventBus.publish(...)` works in tests; use `EventBus.deliver()` to flush before assertions
