// Enterprise STAR entries 1-4: Phase 0 Foundation start

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 1. Salesforce Dev Edition Org Setup + RLM Activation ============
NotionPublishService.EnterpriseEntry e1 = new NotionPublishService.EnterpriseEntry();
e1.title = '01. Salesforce Dev Edition Org Setup + RLM Activation';
e1.situation = new NotionPublishService.SituationSection();
e1.situation.context = 'TechnoStore is a portfolio-quality Salesforce Revenue Lifecycle Management (RLM) demo built for DACH-market job applications. The project begins with a clean Salesforce Developer Edition org as the foundation. Developer Edition is free, persistent, and supports most enterprise features â€” but Industries-licensed products like RLM and CLM are gated and require explicit trial activation.';
e1.situation.problem = 'Out-of-the-box Developer Edition orgs ship without Industries CPQ, Industries Pricing, Order Management, or Contract Lifecycle Management licenses enabled. The metadata exists in the platform but the features are invisible in Setup until the trial license activates them. Without RLM features visible, no Bundle / Configure / Promotional Pricing / Quote-to-Cash demo is possible.';
e1.task = new NotionPublishService.TaskSection();
e1.task.goal = 'Provision a free Developer Edition org with full RLM stack activated (Industries CPQ + Industries Pricing + Order Management + CLM) and authenticate the local Salesforce CLI to it for metadata deployment.';
e1.task.constraints = 'Free Developer Edition limits apply: 5 MB data storage, 20 MB file storage, 100 callouts per Apex execution, 24-hour token expiry on OAuth sessions. No production support contract â€” bugs must be worked around in-org rather than escalated to Salesforce.';
e1.task.successCriteria = 'Setup â†’ Industries â†’ Industries CPQ shows the Pricing Procedure / Product Qualification / Promotional Pricing menus. Setup â†’ Contracts â†’ CLM shows Document Templates, Approval Process, Signer Roles. SF CLI command "sf org display" returns this org as the default target with admin@technostore.example username.';
e1.action = new NotionPublishService.ActionSection();
e1.action.approach = 'Use Salesforce Trial Signup for the Industries Developer org variant (NOT the generic Developer Edition â€” the Industries variant pre-bundles the trial licenses). Authenticate the SF CLI in OAuth Web flow because no connected app is needed for personal-account org access.';
e1.action.implementation = new List<String>{
    'Signed up for a Developer Edition org at developer.salesforce.com/signup using admin@technostore.example as system administrator',
    'Activated the Industries CPQ + RLM trial via Setup â†’ Setup Assistant â†’ Industries Activation (one-time wizard that flips the license switches)',
    'Authenticated SF CLI: sf org login web -a admin@technostore.example â€” opened browser, granted OAuth scope, CLI stored refresh token locally',
    'Set as default org for the project: sf config set target-org=admin@technostore.example inside the TechnoStore repo working directory',
    'Verified Industries features visible: Setup â†’ Industries â†’ Industries CPQ shows Pricing Procedure menu; Setup â†’ Contracts shows CLM templates',
    'Confirmed connection via sf org display â€” returned org id, username, instance URL, API version 60.0'
};
NotionPublishService.CodeSnippet e1c1 = new NotionPublishService.CodeSnippet();
e1c1.caption = 'SF CLI org provisioning';
e1c1.language = 'bash';
e1c1.code = '# Authenticate to Developer Edition org\nsf org login web --alias admin@technostore.example --instance-url https://login.salesforce.com\n\n# Verify connection\nsf org display --target-org admin@technostore.example\n\n# Set as default for this project\nsf config set target-org=admin@technostore.example\n\n# Confirm Industries CPQ activation\nsf data query --query "SELECT Id, Name FROM PricingProcedure LIMIT 5" --target-org admin@technostore.example\nsf data query --query "SELECT Id, Name FROM ProductQualificationProcedure LIMIT 5" --target-org admin@technostore.example';
e1.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e1c1 };
e1.result = new NotionPublishService.ResultSection();
e1.result.outcome = 'Dev Edition org provisioned within 15 minutes. All RLM features visible. SF CLI authenticated and bound to this project directory. Ready to receive metadata deployments and run anonymous Apex against a real RLM-enabled instance.';
e1.result.tradeoffsAndLessons = 'Developer Edition trades production-grade limits (data, callouts, governor) for zero cost and unlimited persistence. The Industries variant is a separate signup path â€” generic Developer Edition does NOT auto-include RLM trial. Trial licenses do not expire on Developer orgs (unlike sandbox trials which expire in 30 days), so this org can serve as a long-running demo environment.';
e1.result.references = new List<String>{
    'developer.salesforce.com/signup â€” Developer Edition signup',
    'help.salesforce.com â†’ Industries CPQ Trial Activation guide',
    'CLAUDE.md â†’ currentDate=2026-05-11 (project active)',
    'Memory: enterprise_apex_layout.md'
};
e1.result.futureWork = 'Sandbox migration plan for production: this Dev Edition will eventually be source-controlled and pushed to a sandbox via sf project deploy. Storage limits will need re-evaluation once data volume exceeds 5 MB (currently at 67% after cleanup).';
entries.add(e1);

// ============ 2. Initial Product Upload via Data Loader ============
NotionPublishService.EnterpriseEntry e2 = new NotionPublishService.EnterpriseEntry();
e2.title = '02. Initial Product Upload via Data Loader â€” CSV Ingestion Pattern';
e2.situation = new NotionPublishService.SituationSection();
e2.situation.context = 'With the Dev Edition org provisioned and RLM activated, the first concrete demo data needed was a base Product2 catalog: workstations, peripherals, cables, software licenses. Initially planned ~30 products. Salesforce Data Loader is the canonical bulk-import tool for Product2, accepting CSV files via the Bulk API path.';
e2.situation.problem = 'Manual product creation via the Salesforce UI is slow (~30 seconds per product including 20+ fields). For 30 products that is 15 minutes of clicking. Worse, every product needs an immediate PricebookEntry in the Standard Pricebook or it cannot appear in Quotes â€” a second round of 30 manual creates.';
e2.task = new NotionPublishService.TaskSection();
e2.task.goal = 'Bulk-load the initial Product2 catalog from CSV files using Salesforce Data Loader, then bulk-load PricebookEntry rows linking each product to the Standard Pricebook with EUR list prices.';
e2.task.constraints = 'Data Loader is a Windows-only desktop app. CSV files must use comma delimiters and UTF-8 encoding. Product2.IsActive must be true. PricebookEntry.UseStandardPrice=false forces an explicit price (true would inherit from Standard which TechnoStore does not use).';
e2.task.successCriteria = '30 Product2 records visible. 30 corresponding PricebookEntry records in the Standard Pricebook with UnitPrice > 0. Quote line item lookup shows all 30 products when typing the first few letters of any name.';
e2.action = new NotionPublishService.ActionSection();
e2.action.approach = 'Two-pass CSV import: first products.csv into Product2 (capturing the generated Salesforce Ids in the export file), then a join step producing pricebookentries.csv with Product2Id + Pricebook2Id (Standard Pricebook lookup) + UnitPrice. Each import is one Data Loader operation.';
e2.action.implementation = new List<String>{
    'Built products.csv with columns: Name, ProductCode, Family, Description, IsActive (all true), QuantityUnitOfMeasure=Each',
    'Authenticated Data Loader with admin@technostore.example OAuth, target endpoint login.salesforce.com',
    'Ran insert into Product2 â€” successful rows exported to products_success.csv with new Salesforce 18-char Ids',
    'Queried Standard Pricebook Id: SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE â€” captured for join step',
    'Built pricebookentries.csv joining products_success.csv with Pricebook2Id=standard + UnitPrice + UseStandardPrice=false + IsActive=true + CurrencyIsoCode=EUR',
    'Ran second insert into PricebookEntry â€” all 30 rows successful',
    'Verified end-to-end by opening a fresh Quote and confirming product lookup finds all 30'
};
NotionPublishService.CodeSnippet e2c1 = new NotionPublishService.CodeSnippet();
e2c1.caption = 'products.csv shape (initial 5 of 30 rows)';
e2c1.language = 'plain text';
e2c1.code = 'Name,ProductCode,Family,Description,IsActive,QuantityUnitOfMeasure\nWorkstation Entry,WS-ENTRY,Workstations,"i5, 16GB RAM, 256GB SSD",true,Each\nWorkstation Standard,WS-STD,Workstations,"i7, 32GB RAM, 512GB SSD",true,Each\nWorkstation Pro,WS-PRO,Workstations,"i9, 64GB RAM, 1TB SSD",true,Each\nWorkstation Mission-Critical,WS-MC,Workstations,"Xeon, 128GB RAM, 2TB SSD",true,Each\nDisplay 27in 4K,DISP-27-4K,Peripherals,"27-inch 4K monitor",true,Each';
NotionPublishService.CodeSnippet e2c2 = new NotionPublishService.CodeSnippet();
e2c2.caption = 'pricebookentries.csv (after Product2 ids captured)';
e2c2.language = 'plain text';
e2c2.code = 'Product2Id,Pricebook2Id,UnitPrice,UseStandardPrice,IsActive,CurrencyIsoCode\n01tA0000001AbcdIAA,01sA00000001XYZAAE,899.00,false,true,EUR\n01tA0000001AbceIAA,01sA00000001XYZAAE,1199.00,false,true,EUR\n01tA0000001AbcfIAA,01sA00000001XYZAAE,1499.00,false,true,EUR\n01tA0000001AbcgIAA,01sA00000001XYZAAE,3499.00,false,true,EUR\n01tA0000001AbchIAA,01sA00000001XYZAAE,449.00,false,true,EUR';
e2.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e2c1, e2c2 };
e2.result = new NotionPublishService.ResultSection();
e2.result.outcome = '30 Product2 records and 30 corresponding PricebookEntry rows inserted in under 3 minutes elapsed (vs. ~30 minutes manual). All products appear in Quote line item lookup. Foundation catalog ready for downstream classification, bundle, and qualification work.';
e2.result.tradeoffsAndLessons = 'Data Loader is faster than manual UI work for any batch over ~5 records, but it has a learning curve: column casing, the Standard Pricebook Id lookup step, and the success-csv-as-input pattern for joins. The same pattern would work via SF CLI bulk import or Apex anonymous DML â€” Data Loader was chosen here because it has a visual progress bar and integrated error CSV for first-time CSV schema validation.';
e2.result.references = new List<String>{
    'developer.salesforce.com â†’ Data Loader download (Windows)',
    'Product2 / PricebookEntry standard objects',
    'Standard Pricebook query: SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE'
};
e2.result.futureWork = 'For ongoing demo data resets, the Apex anonymous path (insert List<Product2>) is preferred over Data Loader because it can be checked into git as scripts/setup_*.apex. The CSV path is retained for first-time bulk loads.';
entries.add(e2);

// ============ 3. Pricebook + PricebookEntry Provisioning ============
NotionPublishService.EnterpriseEntry e3 = new NotionPublishService.EnterpriseEntry();
e3.title = '03. Pricebook + PricebookEntry Provisioning â€” EUR DACH Pricing';
e3.situation = new NotionPublishService.SituationSection();
e3.situation.context = 'TechnoStore targets the DACH market (Germany, Austria, Switzerland) so EUR is the primary currency. Every Product2 needs a PricebookEntry to be sellable on Quotes/Orders. Salesforce ships with a built-in Standard Pricebook that is non-deletable and required as the parent for all custom pricebooks. RLM requires PricebookEntry records even when using the modern PricingProcedure layer.';
e3.situation.problem = 'Without PricebookEntry rows, products are invisible to Quote line item lookup despite existing in Product2. Worse, RLM-aware pricing procedures cannot calculate anything because the entry record carries the catalog membership flag. Multi-currency complicates this: each currency needs its own PricebookEntry per product, multiplying the row count.';
e3.task = new NotionPublishService.TaskSection();
e3.task.goal = 'Create the Standard Pricebook membership for every Product2 with EUR list prices, and structure pricing so the PricingProcedure layer can override the static UnitPrice when needed (promotions, attribute pricing, volume discounts).';
e3.task.constraints = 'CurrencyIsoCode must match an active currency in the org (EUR enabled at org level). UseStandardPrice=false because we want explicit per-product EUR prices. IsActive=true or the entry is invisible. UnitPrice cannot be 0 â€” RLM treats 0-priced PBE as ineligible.';
e3.task.successCriteria = 'Every active Product2 has at least one PricebookEntry in the Standard Pricebook with UnitPrice > 0 EUR. Quote line item lookup returns all expected products. Pricing Procedure engages and overrides UnitPrice when attribute or promotional rules apply.';
e3.action = new NotionPublishService.ActionSection();
e3.action.approach = 'Use anonymous Apex (not Data Loader) for ongoing PricebookEntry management â€” script lives in git, can be re-run idempotently, and handles edge cases like missing entries when new products are added. Define EUR price map per ProductCode.';
e3.action.implementation = new List<String>{
    'Captured Standard Pricebook Id via SOQL once at script start: SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE',
    'Queried all active Product2 records with their ProductCode and Family for price lookup',
    'Built a Map<ProductCode, Decimal> with EUR prices defined per product (Workstation Entry=899, Standard=1199, Pro=1499, MC=3499)',
    'Iterated Product2 list, constructed PricebookEntry per product with Pricebook2Id=standard + UnitPrice from map + UseStandardPrice=false + IsActive=true',
    'Inserted batch via DML â€” logged final count and any missing-price-mapping warnings for products not in the price map'
};
NotionPublishService.CodeSnippet e3c1 = new NotionPublishService.CodeSnippet();
e3c1.caption = 'Apex: PricebookEntry bulk provisioning';
e3c1.language = 'java';
e3c1.code = '// scripts/setup_pricebookentries.apex (re-runnable)\nId standardPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;\n\nMap<String, Decimal> priceMap = new Map<String, Decimal>{\n    \'WS-ENTRY\' => 899.00,\n    \'WS-STD\'   => 1199.00,\n    \'WS-PRO\'   => 1499.00,\n    \'WS-MC\'    => 3499.00,\n    \'DISP-27-4K\' => 449.00,\n    \'KB-MECH\'    => 129.00,\n    \'MOUSE-WIRELESS\' => 49.00\n    // ... 30 entries total\n};\n\nList<Product2> products = [\n    SELECT Id, ProductCode, Name\n    FROM Product2\n    WHERE IsActive = TRUE AND ProductCode IN :priceMap.keySet()\n];\n\nList<PricebookEntry> entries = new List<PricebookEntry>();\nfor (Product2 p : products) {\n    entries.add(new PricebookEntry(\n        Product2Id = p.Id,\n        Pricebook2Id = standardPbId,\n        UnitPrice = priceMap.get(p.ProductCode),\n        UseStandardPrice = false,\n        IsActive = true,\n        CurrencyIsoCode = \'EUR\'\n    ));\n}\ninsert entries;\nSystem.debug(\'Created \' + entries.size() + \' PricebookEntry rows\');';
e3.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e3c1 };
e3.result = new NotionPublishService.ResultSection();
e3.result.outcome = 'All 30 Product2 records have active PricebookEntry rows in the Standard Pricebook at EUR list prices. Quote line item lookup finds every product. Pricing Procedure successfully reads UnitPrice from PBE as the baseline before promotional/attribute adjustments apply.';
e3.result.tradeoffsAndLessons = 'PricebookEntry remains the source-of-truth for "is this product sellable" even in RLM-modern orgs. The PricingProcedure layer reads from PBE; it does not replace it. New products added later must immediately get a PBE row or they will be silently invisible â€” a common debugging gotcha. The Apex-script approach is preferred over Data Loader because scripts can be re-run safely after new products land.';
e3.result.references = new List<String>{
    'scripts/setup_pricebookentries.apex (in repo)',
    'Standard Pricebook always has IsStandard=true and cannot be deleted',
    'PricebookEntry.UseStandardPrice â€” false means override, true means inherit from Standard PB'
};
e3.result.futureWork = 'Multi-currency expansion (CHF for Switzerland, USD for global) requires duplicate PBE rows per currency. The current script is single-currency; extending requires a price-map keyed by (ProductCode, CurrencyIsoCode).';
entries.add(e3);

// ============ 4. TechnoStore Branding ============
NotionPublishService.EnterpriseEntry e4 = new NotionPublishService.EnterpriseEntry();
e4.title = '04. TechnoStore Branding â€” Logo, App Theme, Color Palette';
e4.situation = new NotionPublishService.SituationSection();
e4.situation.context = 'A demo without consistent branding looks like a tutorial. TechnoStore is presented as a real DACH electronics retailer, which means the Salesforce UI, the email templates, the invoice/receipt PDFs, and the Slack notifications all need to share a coherent visual identity: orange-and-blue color palette, the TS logo, and consistent header/footer treatment.';
e4.situation.problem = 'Salesforce out-of-the-box uses generic blue + cloud-white branding. Without customization, screenshots and PDFs look like Trailhead exercises, not a real company. Flying Saucer (the PDF renderer used for branded contracts/invoices) cannot render arbitrary unicode (lightning bolt emoji failed silently), so the logo had to be a properly-sized PNG asset.';
e4.task = new NotionPublishService.TaskSection();
e4.task.goal = 'Build a single source-of-truth for TechnoStore visual identity (logo PNG, primary/secondary colors, footer text), apply it to the Salesforce App, the contract/invoice/receipt PDFs, the customer-facing emails, and the Slack notification block-kit messages.';
e4.task.constraints = 'Logo must be PNG with transparent background, 512x512 recommended for Notion + Salesforce App + emails. Color hex codes must be consistent across CSS, Visualforce, and email templates. Flying Saucer has limited unicode support â€” emoji icons are out, image-based logos are in.';
e4.task.successCriteria = 'Every customer-facing surface (Salesforce App header, contract PDF, invoice PDF, receipt PDF, Slack notifications, customer emails) shows the TechnoStore logo + orange accent color (#FF6B00) + dark blue secondary (#003F7F). No mismatched colors. No emoji icons in PDFs.';
e4.action = new NotionPublishService.ActionSection();
e4.action.approach = 'Define brand tokens once (logo URL, primary hex, secondary hex) and reference them from every surface. Static resource for the logo + reusable Visualforce component for headers + consistent inline CSS in email templates.';
e4.action.implementation = new List<String>{
    'Generated TS logo as 512x512 PNG with transparent background (blue laptop icon with TS text)',
    'Uploaded as Salesforce Static Resource: TechnoStore_Logo (referenced via $Resource.TechnoStore_Logo in VF pages)',
    'Defined brand colors: primary #FF6B00 (TechnoStore orange), secondary #003F7F (dark blue), accent #28A745 (green for receipts)',
    'Built reusable VF component <c:TechnoStoreHeader/> rendering the logo + company name + orange divider',
    'Applied logo to Salesforce App via Setup â†’ App Manager â†’ TechnoStore App â†’ Branding',
    'Embedded logo as base64 inline in HTML emails (some clients block external images by default)'
};
NotionPublishService.CodeSnippet e4c1 = new NotionPublishService.CodeSnippet();
e4c1.caption = 'Reusable VF component: TechnoStoreHeader';
e4c1.language = 'xml';
e4c1.code = '<!-- TechnoStoreHeader.component -->\n<apex:component>\n    <table style="width:100%; border-bottom: 3px solid #FF6B00; margin-bottom: 20px;">\n        <tr>\n            <td style="width:80px; padding:10px;">\n                <apex:image url="{!$Resource.TechnoStore_Logo}"\n                            width="60" height="60"\n                            alt="TechnoStore"/>\n            </td>\n            <td style="vertical-align: middle; padding-left: 15px;">\n                <h1 style="color:#003F7F; margin:0; font-family: Arial, sans-serif;">\n                    TechnoStore\n                </h1>\n                <p style="color:#666; margin:0; font-size: 11px;">\n                    Electronics &amp; Hardware Solutions â€” DACH\n                </p>\n            </td>\n        </tr>\n    </table>\n</apex:component>\n\n<!-- Used in branded PDFs like this -->\n<apex:page renderAs="PDF" applyHtmlTag="false">\n    <c:TechnoStoreHeader/>\n    <!-- content here -->\n</apex:page>';
e4.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e4c1 };
e4.result = new NotionPublishService.ResultSection();
e4.result.outcome = 'Coherent branding across 7 surfaces: Salesforce App header, contract PDF, invoice PDF (orange variant), receipt PDF (green variant), customer email templates, Stripe checkout page metadata, Slack notification block-kit messages. Demo recording looks like a real DACH retailer.';
e4.result.tradeoffsAndLessons = 'Flying Saucer (the VF PDF renderer) is the right choice for portable branded PDFs but has hard limits: no emoji glyphs, limited CSS3, no JavaScript. The lightning-bolt fail taught early in the project to always test renderAs="PDF" with the actual logo asset. The reusable VF component pattern made later additions (invoice PDF, receipt PDF) take 5 minutes each instead of 30.';
e4.result.references = new List<String>{
    'Static Resource: TechnoStore_Logo',
    'VF Component: TechnoStoreHeader',
    'Memory: technostore_branded_pdf_email_system.md',
    'Brand tokens: #FF6B00 / #003F7F / #28A745'
};
e4.result.futureWork = 'Web fonts (currently Arial only) would add typographic polish but Flying Saucer needs explicit @font-face registration. Possible future upgrade if PDF aesthetics become a demo focus.';
entries.add(e4);

// ============ Publish ============
Integer success = 0;
Integer failed = 0;
for (Integer i = 0; i < entries.size(); i++) {
    NotionPublishService.EnterpriseEntry e = entries.get(i);
    try {
        String pageId = NotionPublishService.publishEnterprise(e);
        System.debug('OK [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' -> ' + pageId);
        success++;
    } catch (Exception ex) {
        System.debug('FAIL [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' - ' + ex.getMessage());
        failed++;
    }
}
System.debug('=== BATCH 1 COMPLETE === Success: ' + success + ' / Failed: ' + failed);
