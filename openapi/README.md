# OpenAPI Specifications

Formal **OpenAPI 3.0.3** specifications for the HTTP APIs that TechnoStore **exposes** to external systems. These are the inbound API contracts — any consumer (a webhook sender, a partner integration, a test client) reads these specs to understand the request/response shapes, authentication, error codes.

For the **outbound APIs that TechnoStore calls** (JIRA Cloud, Notion, DocuSign, Stripe, Sendcloud, Slack), see the [Postman collection](../postman/README.md) — those external systems publish their own OpenAPI specs which we do not duplicate here.

## Specification files

| File | Surface | Hosted at |
|------|---------|-----------|
| [`technostore-webhooks.yaml`](technostore-webhooks.yaml) | Salesforce Public Site webhook receivers | `https://*.my.site.com/services/apexrest/*` |
| [`technostore-mule.yaml`](technostore-mule.yaml) | MuleSoft Anypoint HTTP listeners | `https://technostore-mule.cloudhub.io/*` |

## Why two separate specs?

The two API surfaces have different deployment targets, authentication models, and consumers:

| Aspect | `technostore-webhooks.yaml` | `technostore-mule.yaml` |
|--------|-----------------------------|--------------------------|
| Deploy target | Salesforce Public Site (Apex `@RestResource`) | CloudHub 1.0 (Mule HTTP listeners) |
| Authentication | HMAC-SHA256 signature header verification | HMAC-SHA256 + Salesforce OAuth (per endpoint) |
| Primary consumers | DocuSign Connect, future Sendcloud delivery webhook | Stripe Connect webhooks, Salesforce outbound calls |
| Source language | Apex | MuleSoft XML + DataWeave |
| CI/CD | SFDX deploy via GitHub Actions (`.github/workflows/ci.yml`) | Mule deploy via Anypoint Runtime Manager (manual) |

Splitting the specs reflects the deployment + ownership boundary.

## How to consume the specs

### Render locally (Swagger UI)

```bash
# One-off render via npx (no installation)
npx @redocly/cli preview-docs openapi/technostore-webhooks.yaml
npx @redocly/cli preview-docs openapi/technostore-mule.yaml
```

Or with Docker:

```bash
docker run -p 8080:8080 -e SWAGGER_JSON=/spec.yaml \
  -v $(pwd)/openapi/technostore-webhooks.yaml:/spec.yaml \
  swaggerapi/swagger-ui
```

### Validate the specs

```bash
npx @redocly/cli lint openapi/technostore-webhooks.yaml
npx @redocly/cli lint openapi/technostore-mule.yaml
```

### Generate client SDKs (optional)

OpenAPI specs are tool-agnostic — generate a client SDK in any supported language:

```bash
# Java client
openapi-generator-cli generate -i openapi/technostore-mule.yaml -g java -o clients/java

# TypeScript client
openapi-generator-cli generate -i openapi/technostore-mule.yaml -g typescript-axios -o clients/typescript
```

We do not ship generated SDKs in this repo (consumers can generate as needed), but the specs are stable enough to support it.

## Conventions

### Versioning

Each spec has its own `info.version` (semver). Breaking changes bump the major version. The TechnoStore project follows **API-first development** — the spec is authored or updated *before* the implementation changes, so the spec is always the source of truth.

### Error responses

All endpoints return:

- **2xx** — success (`200 OK`, `201 Created`, `204 No Content` per HTTP convention)
- **4xx** — client error with JSON body containing `code` (machine-readable) and `message` (human-readable)
- **5xx** — server error; reserved for internal Salesforce or Mule platform failures

Webhook receivers use:

- **`200 OK`** to acknowledge successful receipt (the external system stops retrying)
- **`400 Bad Request`** for signature verification failures (the external system retries with exponential backoff; if signature is genuinely wrong, the retries also fail — non-recoverable on our side)
- **`401 Unauthorized`** for missing required headers (`Stripe-Signature`, `X-DocuSign-Signature-1`)

### Authentication

Webhook receivers use **HMAC-SHA256 signature verification** rather than OAuth:

- DocuSign: `X-DocuSign-Signature-1` header = base64(HMAC-SHA256(body, DocuSign_Config__c.HMAC_Secret__c))
- Stripe: `Stripe-Signature` header = `t=<timestamp>,v1=<HMAC-SHA256(timestamp + "." + body, mule-app.properties.stripe.webhook.secret)>`

Salesforce outbound calls from Mule use **OAuth 2.0 Username-Password Flow** (External Client App per ADR-001), documented in the Mule spec's `securitySchemes` section.

## Related documentation

- [Postman collection](../postman/README.md) — runnable HTTP requests for both inbound (test the webhooks we expose) and outbound (test the external APIs we call) directions
- [Architecture diagrams](../docs/architecture/) — system-level context for where these APIs sit
- [ADR-003](../docs/adr/ADR-003-site-guest-user-platform-event-indirection.md) — design pattern for the webhook receivers
- [ADR-001](../docs/adr/ADR-001-mule-vs-apex-decision-matrix.md) — why Stripe webhook is on Mule, DocuSign webhook is on Salesforce
