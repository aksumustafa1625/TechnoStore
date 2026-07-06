// Generates a polished 2-page excerpt of the TechnoStore Solution Blueprint
// for use as a Fiverr gig "Document" upload. Highlights architectural maturity.
import { createRequire } from 'node:module';
import fs from 'node:fs';

const require = createRequire('file://' + 'C:/Users/DELL/mustafaaksu-portfolio/');
const PDFDocument = require('C:/Users/DELL/mustafaaksu-portfolio/node_modules/pdfkit');

const OUT = 'C:/Users/DELL/Documents/Projects/TechnoStore/docs/demo/TechnoStore-Solution-Blueprint-Excerpt.pdf';

const NAVY = '#0B2545';
const TEAL = '#13856E';
const GREY = '#444444';
const LIGHT = '#EAF1F5';
const RULE = '#C9D6DF';
const MUTED = '#8A9BA8';

const doc = new PDFDocument({ size: 'A4', margins: { top: 54, bottom: 54, left: 54, right: 54 } });
doc.pipe(fs.createWriteStream(OUT));

const W = doc.page.width;
const L = 54;
const R = W - 54;
const CW = R - L;

function header(title, subtitle) {
  doc.rect(0, 0, W, 96).fill(NAVY);
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(9)
     .text('TechnoStore  ·  Solution Blueprint Excerpt  ·  arc42 v8.2', L, 26, { characterSpacing: 1 });
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(19).text(title, L, 42);
  doc.fillColor('#B9D3E6').font('Helvetica').fontSize(10).text(subtitle, L, 70);
  doc.y = 120;
}

function sectionTitle(t) {
  doc.moveDown(0.2);
  doc.fillColor(TEAL).font('Helvetica-Bold').fontSize(12).text(t, L, doc.y);
  const y = doc.y + 2;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(1).strokeColor(RULE).stroke();
  doc.moveDown(0.35);
}

function para(t) {
  doc.fillColor(GREY).font('Helvetica').fontSize(10.5).text(t, L, doc.y, { width: CW, align: 'left', lineGap: 2.5 });
  doc.moveDown(0.35);
}

function callout(t) {
  const startY = doc.y;
  const padding = 12;
  doc.font('Helvetica-Oblique').fontSize(10.5);
  const h = doc.heightOfString(t, { width: CW - padding * 2, lineGap: 2.5 }) + padding * 2;
  doc.roundedRect(L, startY, CW, h, 6).fill(LIGHT);
  doc.fillColor(NAVY).font('Helvetica-Oblique').fontSize(10.5)
     .text(t, L + padding, startY + padding, { width: CW - padding * 2, lineGap: 2.5 });
  doc.y = startY + h;
  doc.moveDown(0.5);
}

function bullet(label, body) {
  const startY = doc.y;
  doc.fillColor(NAVY).font('Helvetica-Bold').fontSize(10.5).text('• ' + label, L, startY, { width: CW });
  doc.fillColor(GREY).font('Helvetica').fontSize(10.5).text(body, L + 14, doc.y + 1, { width: CW - 14, lineGap: 2 });
  doc.moveDown(0.35);
}

function footerRule(note) {
  const y = doc.page.height - 76;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(1).strokeColor(RULE).stroke();
  doc.fillColor(MUTED).font('Helvetica').fontSize(8.5)
     .text(note, L, y + 8, { width: CW, align: 'left', lineBreak: false });
}

// ============================ PAGE 1 ============================
header('TechnoStore — Solution Blueprint', 'B2B Quote-to-Cash on Salesforce Revenue Cloud  ·  DACH market reference architecture');

sectionTitle('1. Project context');
para(
  'TechnoStore GmbH is a B2B supplier of workstations, peripherals, cables, and software licenses ' +
  'to enterprise IT buyers across the DACH market. The reference implementation models the full ' +
  'Quote-to-Cash (Q2C) lifecycle on Salesforce Revenue Cloud (RLM + CLM) and Industries CPQ, ' +
  'integrating eight external systems for payment, logistics, e-signature, ticketing, messaging, ' +
  'enterprise data sync, and accounting.'
);

sectionTitle('2. Quality goals (priority order)');
bullet('Integration reliability', 'All external systems converge on a single Order activation within ~6 seconds, with HMAC-verified webhooks and idempotent retry handling.');
bullet('DACH market fit', '19% German VAT visible at Quote stage, Sendcloud + DHL parcel routing, lexoffice invoicing, DATEV-konform CSV export, branded B2B PDFs.');
bullet('Architectural defensibility', 'Every significant decision documented as an Architecture Decision Record (ADR) with explicit alternatives considered.');
bullet('Maintainability', '6-package SFDX layout, Kevin O\'Hara TriggerHandler, Selector pattern, Mule-vs-Apex decision matrix.');
bullet('Reviewer scannability', 'README, ADRs, Mermaid diagrams, OpenAPI specs, Postman collection — each artifact answers a specific reviewer question in under 60 seconds.');

sectionTitle('3. Integrated external systems');
para(
  'Eight production-pattern integrations, all demo-verified end-to-end against vendor sandboxes:'
);
para(
  '• Stripe (payment intents + webhook on payment confirmation)\n' +
  '• DocuSign (bidirectional — outbound envelope from Apex + inbound Connect webhook -> Platform Event -> Contract status auto-update)\n' +
  '• Sendcloud / DHL (v3 Orders API for shipping label generation)\n' +
  '• JIRA (bidirectional ticketing; webhook also triggers Order activation)\n' +
  '• Slack (warehouse + ops channels)\n' +
  '• Notion (programmatic STAR-portfolio publishing)\n' +
  '• SAP S/4HANA (7-phase: ATP, sales-order ack, tax, CAMT.053 payment recon, master sync, CloudEvents webhook)\n' +
  '• Twilio WhatsApp (inbound message -> Salesforce Lead with regex email extraction)'
);

footerRule('Mustafa Aksu  ·  arc42 Solution Blueprint  ·  Document version 1.0  ·  Page 1 of 2');

// ============================ PAGE 2 ============================
doc.addPage();
header('TechnoStore — Solution Blueprint', 'Architecture documentation, cross-cutting concepts, quality assurance');

sectionTitle('4. Cross-cutting concepts');
bullet('Webhook security', 'HMAC-SHA256 or shared-secret verification on every inbound endpoint; idempotency via dedicated event-log object.');
bullet('Async after DML', '@future(callout=true) or Queueable for any callout after Approval.process() — prevents "uncommitted work pending" errors.');
bullet('Privilege boundary crossing', 'Site Guest Users publish Platform Events; triggers running under the Automated Process User perform record updates. The intended Salesforce pattern.');
bullet('DACH finance', 'Event-driven lexoffice invoicing on Stripe payment confirmation; DATEV-konform CSV export with SKR04 chart of accounts, German comma decimal, UTF-8 BOM.');
bullet('Documentation as code', '31 Architecture Decision Records (Michael Nygard format), 5 Mermaid architecture diagrams, OpenAPI 3.0 specs, 51-entry STAR-format Notion portfolio.');

sectionTitle('5. Architecture artifacts');
para(
  'The system ships with a layered set of architecture artifacts. Each is scoped to a specific ' +
  'reviewer question:'
);
bullet('arc42 Solution Blueprint', 'Architect-readable overview (this document, full version 626 lines).');
bullet('Architecture Decision Records', '31 ADRs covering: Mule-vs-Apex routing, Site + Guest User inbound pattern, idempotency, SAP integration phases, lexoffice + DATEV, and more.');
bullet('Mermaid architecture diagrams', 'C4 Context + Container + Q2C Sequence + Data Model + CI/CD pipeline.');
bullet('OpenAPI 3.0 specifications', 'Inbound webhook contracts published for every external system.');
bullet('Notion STAR portfolio', '51 STAR-format case-study entries, generated programmatically via a custom Apex Notion-publishing service.');

sectionTitle('6. Quality assurance summary');
callout(
  'Six-package SFDX layout. Kevin O\'Hara TriggerHandler framework with recursion guards and ' +
  'bypass mechanism. Full Apex test coverage on every shipped class. FLS/CRUD enforcement via ' +
  'WITH USER_MODE on every read. Demo-verified end-to-end against vendor sandboxes — every ' +
  'flow has been observed working with real or sandbox traffic.'
);

footerRule('Mustafa Aksu  ·  arc42 Solution Blueprint  ·  Document version 1.0  ·  Page 2 of 2');

doc.end();
console.log('Wrote ' + OUT);
