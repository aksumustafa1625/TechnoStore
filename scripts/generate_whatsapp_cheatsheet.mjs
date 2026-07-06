// Generates a 2-page interview cheat-sheet PDF for the WhatsApp -> Salesforce integration.
// Page 1: English. Page 2: German. Uses the pdfkit already installed in the portfolio repo.
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire('file://' + 'C:/Users/DELL/mustafaaksu-portfolio/');
const PDFDocument = require('C:/Users/DELL/mustafaaksu-portfolio/node_modules/pdfkit');

const OUT = 'C:/Users/DELL/Documents/Projects/TechnoStore/docs/demo/WhatsApp-Interview-CheatSheet.pdf';

// --- palette ---
const NAVY = '#0B2545';
const TEAL = '#13856E';
const GREY = '#444444';
const LIGHT = '#EAF1F5';
const RULE = '#C9D6DF';

const doc = new PDFDocument({ size: 'A4', margins: { top: 54, bottom: 54, left: 54, right: 54 } });
doc.pipe(fs.createWriteStream(OUT));

const W = doc.page.width;
const L = 54;
const R = W - 54;
const CW = R - L;

function header(flagLabel, title, subtitle) {
  doc.rect(0, 0, W, 96).fill(NAVY);
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(9)
     .text('TechnoStore  ·  Interview Cheat-Sheet', L, 26, { characterSpacing: 1 });
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(19).text(title, L, 42);
  doc.fillColor('#B9D3E6').font('Helvetica').fontSize(10).text(subtitle, L, 70);
  // language chip
  const chipW = 70;
  doc.roundedRect(R - chipW, 30, chipW, 22, 11).fill(TEAL);
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(11)
     .text(flagLabel, R - chipW, 36, { width: chipW, align: 'center' });
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

function scriptBox(t) {
  const startY = doc.y;
  const padding = 12;
  doc.font('Helvetica-Oblique').fontSize(10.5);
  const h = doc.heightOfString(t, { width: CW - padding * 2, lineGap: 2.5 }) + padding * 2;
  doc.roundedRect(L, startY, CW, h, 6).fill(LIGHT);
  doc.fillColor(NAVY).font('Helvetica-Oblique').fontSize(10.5)
     .text(t, L + padding, startY + padding, { width: CW - padding * 2, lineGap: 2.5 });
  doc.y = startY + h;
  doc.moveDown(0.6);
}

function qa(q, a) {
  doc.fillColor(NAVY).font('Helvetica-Bold').fontSize(10.5).text(q, L, doc.y, { width: CW });
  doc.fillColor(GREY).font('Helvetica').fontSize(10.5).text(a, L, doc.y + 1, { width: CW, lineGap: 2 });
  doc.moveDown(0.5);
}

function footerRule(note) {
  const y = doc.page.height - 76;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(1).strokeColor(RULE).stroke();
  doc.fillColor('#8A9BA8').font('Helvetica').fontSize(8.5)
     .text(note, L, y + 8, { width: CW, align: 'left', lineBreak: false });
}

// ============================ PAGE 1 — ENGLISH ============================
header('EN', 'WhatsApp -> Salesforce', 'How I built it  ·  what to say when asked');

sectionTitle('The one-paragraph answer');
scriptBox(
  'When a customer sends a WhatsApp message, Twilio receives it. Twilio is the messaging ' +
  'provider — it talks to WhatsApp for us, so we don’t connect to Meta directly. Twilio then ' +
  'calls a webhook in Salesforce: a public URL that listens for incoming data. I built that URL ' +
  'as an Apex REST service (WhatsAppWebhookRestService), exposed through a Salesforce Site with a ' +
  'guest user. The service does three things: it checks a secret key so only Twilio can call it, ' +
  'it creates a Lead from the message (phone, email, and text), and it replies automatically to ' +
  'the customer. I also added two production-grade details: idempotency — if Twilio retries the ' +
  'same message, we still create only one Lead, because I track the unique MessageSid — and ' +
  'error logging, so no failure is lost silently.'
);

sectionTitle('If they go deeper');
qa('"Is this production-ready?"',
   'The code is. For production we switch the Twilio Sandbox number to a verified WhatsApp Business ' +
   'number from Meta, validate Twilio’s signature instead of a query secret, and add GDPR consent ' +
   '— important for the DACH market. Same Apex code.');
qa('"Why a Lead and not a Case?"',
   'A Lead because it is a new, unknown contact reaching out. For an existing customer asking for ' +
   'support, the same pattern would create a Case instead — a small change in the service.');
qa('"Why Apex and not MuleSoft?"',
   'For a single, simple inbound webhook, Apex is direct and fast. With many systems, or if we needed ' +
   'retries, queuing and routing, I’d put it behind MuleSoft — same contract, only the URL changes. ' +
   'That matches how I built the SAP layer.');

sectionTitle('Honesty rule (protects you)');
para('Do NOT call this "Salesforce Headless Identity". It is a webhook / API integration ' +
     '(Twilio -> Apex REST -> Lead). If someone uses the wrong label, correct it gently — that ' +
     'precision makes you look senior, not junior.');

sectionTitle('Is this novel? (build vs buy)');
para('No — WhatsApp-to-CRM is common, and Salesforce offers it natively through Digital Engagement ' +
     '(a paid Service Cloud add-on). I built the custom webhook version to show the engineering, not ' +
     'to claim a new feature. Custom = no extra license and full control of routing and object mapping ' +
     '(Lead today, Case for known customers). Native = faster if you already pay for Digital Engagement. ' +
     'Knowing both — and when to choose each — is the senior signal. In DACH I would gate it behind ' +
     'DSGVO consent, not capture every message.');

footerRule('Mustafa Aksu  ·  TechnoStore demo  ·  8th external integration (with SAP, DocuSign, Stripe, lexoffice …)');

// ============================ PAGE 2 — GERMAN ============================
doc.addPage();
header('DE', 'WhatsApp -> Salesforce', 'Wie ich es gebaut habe  ·  was du im Gespräch sagst');

sectionTitle('Die Antwort in einem Absatz');
scriptBox(
  'Wenn ein Kunde eine WhatsApp-Nachricht sendet, empfängt Twilio sie. Twilio ist der ' +
  'Messaging-Anbieter — er spricht für uns mit WhatsApp, also verbinden wir uns nicht direkt mit ' +
  'Meta. Dann ruft Twilio einen Webhook in Salesforce auf: eine öffentliche URL, die auf eingehende ' +
  'Daten wartet. Diese URL habe ich als Apex-REST-Service gebaut (WhatsAppWebhookRestService), über ' +
  'eine Salesforce-Site mit einem Gast-Benutzer. Der Service macht drei Dinge: Er prüft einen ' +
  'geheimen Schlüssel, damit nur Twilio ihn aufrufen kann, er erstellt einen Lead aus der Nachricht ' +
  '(Telefon, E-Mail und Text) und er antwortet automatisch dem Kunden. Ich habe auch zwei ' +
  'produktionsreife Details hinzugefügt: Idempotenz — wenn Twilio dieselbe Nachricht erneut sendet, ' +
  'erstellen wir trotzdem nur einen Lead, weil ich die eindeutige MessageSid speichere — und ' +
  'Fehler-Logging, damit kein Fehler still verloren geht.'
);

sectionTitle('Wenn sie tiefer fragen');
qa('"Ist das produktionsreif?"',
   'Der Code ja. Für die Produktion wechseln wir die Twilio-Sandbox-Nummer zu einer verifizierten ' +
   'WhatsApp-Business-Nummer von Meta, prüfen die Twilio-Signatur statt eines Query-Secrets und ' +
   'fügen DSGVO-Einwilligung hinzu — wichtig für den DACH-Markt. Der Apex-Code bleibt gleich.');
qa('"Warum ein Lead und kein Case?"',
   'Ein Lead, weil es ein neuer, unbekannter Kontakt ist. Für einen bestehenden Kunden mit einer ' +
   'Support-Anfrage würde dasselbe Muster einen Case erstellen — nur eine kleine Änderung im Service.');
qa('"Warum Apex und nicht MuleSoft?"',
   'Für einen einzelnen, einfachen eingehenden Webhook ist Apex direkt und schnell. Bei vielen ' +
   'Systemen, oder wenn wir Retries, Queuing und Routing bräuchten, würde ich es hinter MuleSoft ' +
   'legen — gleicher Vertrag, nur die URL ändert sich. So habe ich auch die SAP-Schicht gebaut.');

sectionTitle('Ehrlichkeits-Regel (zu deinem Schutz)');
para('Nenne das NICHT "Salesforce Headless Identity". Es ist eine Webhook-/API-Integration ' +
     '(Twilio -> Apex REST -> Lead). Wenn jemand das falsche Label benutzt, korrigiere es freundlich ' +
     '— genau diese Präzision lässt dich senior wirken, nicht junior.');

sectionTitle('Ist das neu? (build vs buy)');
para('Nein — WhatsApp-zu-CRM ist verbreitet, und Salesforce bietet es nativ über Digital Engagement an ' +
     '(ein kostenpflichtiges Service-Cloud-Add-on). Ich habe die Custom-Webhook-Variante gebaut, um das ' +
     'Engineering zu zeigen, nicht um ein neues Feature zu behaupten. Custom = keine zusätzliche Lizenz ' +
     'und volle Kontrolle über Routing und Objekt-Mapping (heute Lead, Case für bekannte Kunden). Nativ ' +
     '= schneller, wenn man Digital Engagement schon bezahlt. Beides zu kennen — und zu wissen, wann man ' +
     'was wählt — ist das Senior-Signal.');

sectionTitle('Aussprache-Tipps');
para('Idempotenz = "ee-dem-po-TENTS"   ·   Gast-Benutzer = "gast be-NUT-ser"   ·   ' +
     'eingehender Webhook = "AYN-gay-ender web-hook"');

footerRule('Mustafa Aksu  ·  TechnoStore Demo  ·  8. externe Integration (mit SAP, DocuSign, Stripe, lexoffice …)');

doc.end();
console.log('Wrote ' + OUT);
