# SAP Integration via MuleSoft — Setup Guide

> **Status:** Phase 2 of the SAP integration roadmap (sprint 68 ticket TS-3). Establishes the **Mule side** of the SAP integration in parallel with the Apex side (Phase 1, completed). Both layers query the same SAP API Hub Sandbox endpoint.

## What this flow does

`sap-integration-FULL.xml` defines `sap-test-businesspartner-query` — a Mule flow that:

1. **Listens on `http://localhost:8081/sap/test/bp`** for a POST (or GET) trigger
2. **Calls SAP S/4HANA Cloud Sandbox** via `https://sandbox.api.sap.com/.../A_BusinessPartner?$top=5`
3. **Parses the OData v2 response** (`d.results[]` array)
4. **Logs each Business Partner** at INFO level in the Mule console
5. **Returns a SUCCESS JSON response** to the HTTP caller

It is the **MuleSoft equivalent** of the Apex smoke test (`scripts/test_sap_business_partner_query.apex` — already verified in Phase 1 with 5 BP records returned).

Running both layers against the same Sandbox proves the integration is reachable from either side, which is what subsequent phases need:

- **Phase 3 (TS-4):** Account → SAP BusinessPartner sync — runs on Mule
- **Phase 4 (TS-5):** Order → SAP Sales Order replication — runs on Mule
- **Phase 5 (TS-6):** SAP polling for bidirectional sync — runs on Mule

## Architecture

```
[Anypoint Studio — Mule local runtime]
    │
    ▼ HTTP listener on port 8081
[Postman / curl]
    POST http://localhost:8081/sap/test/bp
        ↓
[Mule flow: sap-test-businesspartner-query]
    HTTP Request:
        GET https://sandbox.api.sap.com/s4hanacloud/sap/opu/odata/sap/
            API_BUSINESS_PARTNER/A_BusinessPartner?$top=5&$format=json
        Headers: APIKey, Accept
        ↓
[SAP S/4HANA Cloud Sandbox]
    Real SAP server response with 5 Business Partners
        ↓
[Mule DataWeave transform]
    Parses d.results[] → simplified BP array
        ↓
[Mule console]
    INFO log: SAP BP: 11 [Organization] / Cust15 Cust15
    INFO log: SAP BP: 202 [Organization] / Nue tech inc
    INFO log: SAP BP: 203 [Organization] / Expo technologies Plc
    INFO log: SAP BP: 1018 [Organization] / Bechtle AG Kriek street
    INFO log: SAP BP: 1710 [Organization] / Inlandskunde DE 80
        ↓
[HTTP response back to Postman]
    {"status": "SUCCESS", "message": "Mule successfully queried..."}
```

## One-time setup (5 minutes)

### 1. Open your Anypoint Studio project

If you have an existing Mule project (the same one containing `inventory-jira-ticket-flow`), use that. Otherwise create a new Mule project (File → New → Mule Project) and name it `technostore-integration`.

### 2. Copy `sap-integration-FULL.xml` into the project

Drag/drop `mulesoft/sap-integration-FULL.xml` into `src/main/mule/` in the Package Explorer. Anypoint Studio will parse the XML and add the flow + the configs.

### 3. Update `src/main/resources/dev.yaml`

If `dev.yaml` exists, add the `sap:` section at the bottom:

```yaml
sap:
  host: "sandbox.api.sap.com"
  api:
    key: "PASTE_YOUR_SAP_API_HUB_API_KEY_HERE"
```

If `dev.yaml` does not exist, copy from `mulesoft/dev.yaml.template`:

```bash
cp mulesoft/dev.yaml.template <your-mule-project>/src/main/resources/dev.yaml
```

Then replace `REPLACE_WITH_YOUR_SAP_API_HUB_API_KEY` with the real key (same key used in `scripts/setup_sap_config.apex` for the Apex side).

**Critical:** `dev.yaml` is gitignored. Never commit it with real credentials.

### 4. Run the Mule app in Anypoint Studio

In Package Explorer, right-click the project → **Run As** → **Mule Application**. The Mule console will boot the runtime + listener:

```
INFO  ... 'sap-test-businesspartner-query' initialized
INFO  ... Listening on http://0.0.0.0:8081
```

If you see `Address already in use: bind` on port 8081, another Mule app is running on the same port. Stop the other app or change `http:listener-config` port in this XML.

### 5. Trigger the test via Postman

```
POST http://localhost:8081/sap/test/bp
(No body, no auth headers needed — local-only)
```

**Expected response (JSON):**

```json
{
    "status": "SUCCESS",
    "message": "Mule successfully queried SAP S/4HANA Cloud Sandbox",
    "source": "Mule sap-test-businesspartner-query flow",
    "apexEquivalent": "scripts/test_sap_business_partner_query.apex",
    "note": "If you see 5 BP records in the Mule console log, integration is verified end-to-end."
}
```

**Expected Mule console output:**

```
INFO  ... SAP BP test triggered — calling sandbox.api.sap.com...
INFO  ... SAP HTTP response received — parsing...
INFO  ... SAP BP: 11 [Organization] / Cust15 Cust15
INFO  ... SAP BP: 202 [Organization] / Nue tech inc
INFO  ... SAP BP: 203 [Organization] / Expo technologies Plc
INFO  ... SAP BP: 1018 [Organization] / Bechtle AG Kriek street
INFO  ... SAP BP: 1710 [Organization] / Inlandskunde DE 80
INFO  ... SAP integration test SUCCESS — Mule + Apex both verified against API Hub Sandbox.
```

If you see this **the same 5 BP records the Apex Phase 1 smoke test returned**, Phase 2 is verified.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` on SAP request | `dev.yaml` has wrong/placeholder `sap.api.key` | Paste real key from api.sap.com |
| `Address already in use: bind` | Another Mule app on port 8081 | Stop it OR change port in `http:listener-config` |
| `ConnectionException: Connection refused` from Postman | Mule app not started in Anypoint Studio | Right-click project → Run As → Mule Application |
| Empty `businessPartners` array | SAP returned 0 BPs (unusual for sandbox) | Check raw response: temporarily add `<logger message="#[payload]"/>` before the DataWeave |
| `HTTP 503` from SAP | API Hub Sandbox temporary outage | Wait 1-2 minutes, retry |

## Cross-reference

| Layer | Artifact | Status |
|-------|----------|--------|
| Apex side | `scripts/test_sap_business_partner_query.apex` | ✅ Phase 1 verified |
| Mule side | `mulesoft/sap-integration-FULL.xml` | ✅ Phase 2 (this guide) |
| Custom Setting | `SAP_Config__c` (Salesforce) | ✅ Phase 1 |
| Mule credentials | `dev.yaml` (gitignored) | Local-only |
| Remote Site | `SAP_API_Hub` (Salesforce) | ✅ Phase 1 |

## Next steps

After Phase 2 verified, proceed to:

- **Phase 3 (TS-4):** Account → SAP BusinessPartner sync — add `salesforce:replay-channel-listener` to subscribe to `/event/Account_Sap_Sync_Requested__e` and POST to SAP A_BusinessPartner endpoint
- **Phase 4 (TS-5):** Order activation → SAP Sales Order replication — the primary integration goal

Both phases reuse the `SAP_HTTP_Config` defined in this XML.
