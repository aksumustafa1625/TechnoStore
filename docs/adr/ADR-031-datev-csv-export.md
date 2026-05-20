# ADR-031: DATEV Buchungsstapel CSV Export (Steuerberater Segment)

## Status

Accepted — implemented 2026-05-20. `DatevExportService` deployed and tested; generates a DATEV-konform "Buchungsstapel" CSV (format EXTF 700, category 21) from a standard **Invoice** (Industries Billing) using SKR04 accounts, attaches it to the invoice as a ContentVersion. File-based counterpart to ADR-030 (lexoffice real-time API). (An earlier draft targeted the custom Demo_Invoice__c; pivoted to standard Invoice for cohesion with the Stripe/SAP flow.)

## Context

Per ADR-030, the DACH accounting market has two segments. lexoffice covers SME cloud-native (real-time API). The other half — larger firms and anyone working with a tax advisor — uses **DATEV**, the dominant platform for Germany's 40,000+ Steuerberater. The standard interchange is the **DATEV-Format "Buchungsstapel"**: a CSV the source system generates and the Steuerberater imports into DATEV Kanzlei-Rechnungswesen.

"DATEV-konform export" is a de facto requirement for B2B software sold in Germany. Showing it — even file-based — signals the developer understands German accounting reality, not just generic REST integration.

Why CSV and not the DATEVconnect Online API:
- DATEVconnect requires DATEV partner registration, a paid DATEV-Konto, and an approval process (weeks). Not feasible for a demo.
- The CSV "Buchungsstapel" is a public, documented format. No gatekeeping. It's also what most real Steuerberater workflows actually use.
- The trade-off (no automatic appearance in DATEV) is exactly why lexoffice (ADR-030) exists alongside it — lexoffice provides the real-time visible path, DATEV provides the Steuerberater-standard audit path.

## Decision

`DatevExportService` (`force-app-services`) builds a three-section DATEV Buchungsstapel CSV:

1. **EXTF header** — format 700, category 21 (Buchungsstapel), with consultant/client placeholders, fiscal-year start, booking period, EUR currency.
2. **Column header row** — DATEV standard German column names (Umsatz, Soll/Haben-Kennzeichen, Konto, Gegenkonto, BU-Schlüssel, Belegdatum, Belegfeld 1, Buchungstext, …).
3. **Booking row(s)** — one row per invoice representing the sales posting.

Chart of accounts: **SKR04** (modern German standard).
- Revenue: **4400** (Erlöse 19% USt) — SKR04 revenue accounts auto-apply 19% VAT, so no explicit BU-Schlüssel needed.
- Customer (Debitor): **Invoice.BillingAccount.DATEV_Debitor_Number__c**, SKR04 range 10000–69999, auto-allocated sequentially from 10001 if the Account has none.

Amount source: `Invoice.TotalAmountWithTax` (gross); `Invoice.DocumentNumber` → Belegfeld 1; `BillingAccount.Name` → Buchungstext.

Booking representation: `Umsatz` = gross, `Soll/Haben-Kennzeichen` = "S", `Konto` = Debitor, `Gegenkonto` = 4400.

The CSV is attached to the invoice as a **ContentVersion** so it's downloadable from the record (and emailable to the Steuerberater).

### German locale specifics (handled, common bug sources)

- **Decimal separator is comma**: `1449,00` not `1449.00` (via `germanDecimal()`).
- **Belegdatum is DDMM** (4 digits): `2005` = 20 May; the year comes from the EXTF header's fiscal year.
- **Field separator** is semicolon `;`; text fields double-quoted with `""` escaping.

### Verified output (DOC-000000002, Dickenson plc, 7,99 EUR)

```
"EXTF";700;21;"Buchungsstapel";9;20260520...;;"RE";"TechnoStore";"";1;1;20260101;4;20260403;20260403;"TechnoStore Export";"";1;;;"EUR";...
Umsatz (ohne Soll/Haben-Kz);Soll/Haben-Kennzeichen;WKZ Umsatz;...;Konto;Gegenkonto (ohne BU-Schlüssel);BU-Schlüssel;Belegdatum;Belegfeld 1;...;Buchungstext
7,99;"S";"EUR";;;;10002;4400;;"0304";"DOC-000000002";"";;"Rechnung Dickenson plc"
```

(German comma decimal, SKR04 Debitor 10002 auto-allocated, revenue 4400, Belegdatum DDMM "0304", DocumentNumber as Belegfeld 1 — all verified against the standard Invoice.)

## Consequences

### Positive

- **DACH-konform signal** — recruiter sees SKR04 accounts, German number/date formatting, Buchungsstapel structure. Niche knowledge few Salesforce devs have.
- **No external dependency** — pure generation; works offline, no API key, no trial expiry. The most durable integration in the portfolio.
- **Complements lexoffice** — together (ADR-030 + ADR-031) they cover both DACH accounting segments; the dual-coverage story is stronger than either alone.

### Negative

- **No automatic DATEV-side record** — by design (DATEV imports the file). This is the deliberate division of labour with lexoffice. Narrated honestly: DATEV is the Steuerberater workflow, lexoffice is the real-time one.
- **Account mapping is demo-simplified** — production needs the Steuerberater to confirm the exact Konto/Gegenkonto mapping, Wirtschaftsjahr alignment, and any BU-Schlüssel for special tax cases. Documented as the go-live validation step.
- **Encoding** — Apex `Blob.valueOf()` produces UTF-8; strict DATEV imports may expect Windows-1252. German umlauts in company names are the risk. Production should transcode to Win-1252 (or rely on DATEV's UTF-8-with-BOM acceptance). Noted as a hardening item.

### Neutral

- One booking row per invoice (the common single-line sales representation). Multi-line postings (e.g., separate VAT line, Skonto) are a straightforward extension if needed.

## Production migration

1. Steuerberater validates account mapping (Konto/Gegenkonto, BU-Schlüssel) against the client's SKR04/SKR03 setup.
2. Add Windows-1252 encoding for the CSV blob.
3. Optionally batch multiple invoices into one Buchungsstapel per period rather than one file per invoice.
4. Optionally email the file to the Steuerberater automatically on a monthly schedule (Scheduled Apex).

## References

- `force-app-services/main/default/classes/DatevExportService.cls`
- `force-app/main/default/objects/Account/fields/DATEV_Debitor_Number__c.field-meta.xml`
- `scripts/test_datev_export.apex`, `scripts/view_datev_csv.apex`
- DATEV format spec: <https://developer.datev.de/datev/platform/de/dtvf/formate/header>
- ADR-030 — lexoffice integration (SME segment, real-time API counterpart)
