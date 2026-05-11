// Bulk publish STAR entries 1-7: Salesforce Core + CLM start

List<NotionPublishService.StarEntry> entries = new List<NotionPublishService.StarEntry>();

// ===== 1. RLM Product Qualification — Workstation Tier Filtering =====
NotionPublishService.StarEntry e1 = new NotionPublishService.StarEntry();
e1.title = '1. RLM Product Qualification — Workstation Tier Filtering';
e1.situation = 'TechnoStore offers 5 workstation tiers (Entry/Standard/Pro/Workgroup/Mission-Critical) across DACH market accounts of very different sizes — Hamburg DataWorks (200 employees, large enterprise) vs Köln Retail Cloud (50 employees, mid-market). Without product qualification logic, every account saw every tier in Browse Catalog, leading to poor recommendations and overwhelming UX.';
e1.taskText = 'Implement multi-tier product visibility filtering driven by Account.NumberOfEmployees so large enterprises see all 5 workstation tiers while mid-market accounts see only the Entry tier.';
e1.actions = new List<String>{
    'Created 5 ProductQualificationCategory records keyed on Account.NumberOfEmployees ranges (0-50, 51-200, 201-1000, 1001-5000, 5000+)',
    'Built ProductQualificationProcedure with employee-count-based eligibility steps targeting BasedOnId of each Workstation classification',
    'Diagnosed Product2.Type field gotcha — must be NULL (not "Base") for products to enter the qualification pipeline; updating Type is blocked, must recreate',
    'Required two-step sync after every product config change: Product Discovery Index rebuild + Salesforce Pricing Setup Sync — automated in setup_workstation_catalog.apex',
    'Verified live in Browse Catalog: Hamburg sees 4 tiers, Köln sees 1 tier, switching account context updates filter in real time'
};
e1.result = 'Live differential catalog working. Hamburg DataWorks sees Entry + Standard + Pro + Mission-Critical (4 workstations), Köln Retail Cloud sees only Entry (1 workstation). The same product catalog, contextually filtered per account size. Production-pattern Industries CPQ feature demonstrated.';
NotionPublishService.CodeSnippet e1c1 = new NotionPublishService.CodeSnippet();
e1c1.caption = 'ProductQualificationCategory setup (Apex)';
e1c1.language = 'java';
e1c1.code = 'ProductQualificationCategory pqc = new ProductQualificationCategory(\n    Name = \'Enterprise Workstations\',\n    BasedOnId = workstationClassificationId,\n    Description = \'200+ employee accounts see Pro/Mission-Critical tiers\'\n);\ninsert pqc;\n\nProductQualificationProcedure proc = [\n    SELECT Id FROM ProductQualificationProcedure\n    WHERE Name = \'Workstation Employee Tier Filter\' LIMIT 1\n];\n// Run Product Discovery sync + Pricing Setup Sync after insert';
e1.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e1c1 };
entries.add(e1);

// ===== 2. RLM Spring Sale Promotional Pricing — Date-Windowed =====
NotionPublishService.StarEntry e2 = new NotionPublishService.StarEntry();
e2.title = '2. RLM Spring Sale 2026 — Date-Windowed Promotional Pricing';
e2.situation = 'Marketing requested a Spring Sale 2026 promotion running May 1-31 with auto-activated discounts on qualifying workstation products. Manual price overrides risk bleeding into off-sale periods — once you change UnitPrice, you have to remember to revert it. The native Pricing Procedure must engage and disengage automatically based on current date.';
e2.taskText = 'Build a date-driven promotional discount that engages automatically when today falls within the configured window, on specific qualifying products only, with zero manual intervention before/after.';
e2.actions = new List<String>{
    'Created PricePromoMatrix record with EffectiveDate=2026-05-01 and ExpirationDate=2026-05-31',
    'Configured PricingProcedureStep with DateBased eligibility evaluating System.now() against PromoMatrix dates',
    'Linked QualifierGroup to specific Product2 records (Workstation Pro, Workstation Standard) — not all products eligible',
    'Set discount type to PercentageOff with 13.3% off (€1,499 → €1,299 demo target)',
    'Tested with Apex date mocks and reverse-system-time scenarios to verify auto-revert outside window'
};
e2.result = 'Workstation Pro displays €1,499 base price normally. During May 1-31 Spring Sale window, line item auto-shows €1,299 with discount applied at the Pricing Procedure level. Reverts to €1,499 automatically on June 1. No human intervention required.';
NotionPublishService.CodeSnippet e2c1 = new NotionPublishService.CodeSnippet();
e2c1.caption = 'PricePromoMatrix + step (Apex)';
e2c1.language = 'java';
e2c1.code = 'PricePromoMatrix promo = new PricePromoMatrix(\n    Name = \'Spring Sale 2026\',\n    EffectiveDate = Date.newInstance(2026,5,1),\n    ExpirationDate = Date.newInstance(2026,5,31),\n    DiscountType = \'PercentageOff\',\n    Value = 13.3\n);\ninsert promo;\n\nPricingProcedureStep step = new PricingProcedureStep(\n    PricingProcedureId = ppId,\n    StepType = \'DateBasedDiscount\',\n    EligibilityCriteria = \'EffectiveDate <= TODAY AND ExpirationDate >= TODAY\'\n);\ninsert step;';
e2.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e2c1 };
entries.add(e2);

// ===== 3. Bundle Attribute Pricing — Custom Metadata Workaround =====
NotionPublishService.StarEntry e3 = new NotionPublishService.StarEntry();
e3.title = '3. Bundle Attribute Pricing — Custom Metadata Workaround';
e3.situation = 'Native RLM Pricing Procedure for bundle attribute-based price adjustments (e.g., RAM upgrade from 16GB to 32GB on Workstation Pro adding €200) had 0 steps despite valid AttributeBasedAdjustment records existing. The Pricing Procedure Builder UI is brittle — Salesforce CSM advised against editing live procedures during demo prep. Native engine path blocked.';
e3.taskText = 'Implement attribute-based pricing for bundle configurations without depending on the broken native engine, while keeping data structures compatible so production migration is config-only.';
e3.actions = new List<String>{
    'Designed Techno_Attribute_Price_Rule__mdt Custom Metadata Type with fields: Product2_Id, Attribute_Name, Attribute_Value, Price_Adjustment',
    'Built AttributePricingHandler @future trigger on QuoteLineItem after-insert/after-update',
    'Trigger reads QuoteLineItem attributes (RAM, Storage), queries matching mdt rule, adjusts UnitPrice in-place via DML update',
    'Mirrored data layer 1:1 with AttributeBasedAdjustment schema so feature is config-only swap once native engine is fixed',
    'Documented as workaround in bundle_attribute_pricing_trigger.md memory for future maintainability'
};
e3.result = 'Configuring 32GB RAM on Workstation Pro adds €200 to line price via Custom Metadata lookup within ~2 seconds (@future async). Same data layer feeds either engine — when Salesforce fixes native we flip a feature flag, no migration needed.';
NotionPublishService.CodeSnippet e3c1 = new NotionPublishService.CodeSnippet();
e3c1.caption = 'AttributePricingHandler @future method';
e3c1.language = 'java';
e3c1.code = '@future\npublic static void recalcAttributePricing(Set<Id> qliIds) {\n    Map<String, Techno_Attribute_Price_Rule__mdt> rules =\n        Techno_Attribute_Price_Rule__mdt.getAll();\n\n    List<QuoteLineItem> qlis = [\n        SELECT Id, Product2Id, UnitPrice, Configured_RAM__c\n        FROM QuoteLineItem WHERE Id IN :qliIds\n    ];\n    for (QuoteLineItem q : qlis) {\n        String key = q.Product2Id + \'|RAM|\' + q.Configured_RAM__c;\n        Techno_Attribute_Price_Rule__mdt rule = rules.get(key);\n        if (rule != null) q.UnitPrice += rule.Price_Adjustment__c;\n    }\n    update qlis;\n}';
e3.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e3c1 };
entries.add(e3);

// ===== 4. Quote Tax Display — Formula Field Workaround =====
NotionPublishService.StarEntry e4 = new NotionPublishService.StarEntry();
e4.title = '4. Quote Tax Display — Formula Field Workaround';
e4.situation = 'TechnoStore is DACH-focused and 19% German VAT must be visible on Quote/QuoteLineItem before Order creation for sales-stage transparency. The configured commercetax.TaxEngineAdapter only fires during Invoice creation — Quote stage shows raw UnitPrice with no tax. Sales team needs net + VAT + gross visible during proposal stage.';
e4.taskText = 'Display the €X (Net) + 19% VAT = €Y (Gross) breakdown directly on Quote layout without rebuilding the tax engine or duplicating logic.';
e4.actions = new List<String>{
    'Built 4 formula fields: QuoteLineItem.Tax_Rate__c (19%), QuoteLineItem.Tax_Amount__c (UnitPrice * 0.19), Quote.Total_Tax__c (rollup sum), Quote.Total_With_VAT__c (TotalPrice + Total_Tax__c)',
    'Used currency formula fields (not text) so they participate in Quote PDF generation and reporting',
    'Verified commercetax adapter chain still fires intact at Invoice creation — no regression for production tax engine',
    'Established two-stage demo narrative: Quote shows estimated VAT (formula), Invoice shows official tax (adapter computed)',
    'Avoided Apex trigger path which would have created circular calc with the Pricing Procedure'
};
e4.result = 'Quote line items now display "€1,499.00 + €284.81 VAT = €1,783.81" immediately on save with zero Apex execution. Invoice creation still triggers full commercetax engine for legal compliance. Sales team has price transparency, finance team keeps engine integrity.';
NotionPublishService.CodeSnippet e4c1 = new NotionPublishService.CodeSnippet();
e4c1.caption = 'Formula field definitions';
e4c1.language = 'xml';
e4c1.code = '<!-- QuoteLineItem.Tax_Amount__c -->\n<fullName>Tax_Amount__c</fullName>\n<formula>UnitPrice * 0.19</formula>\n<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n<type>Currency</type>\n<precision>18</precision>\n<scale>2</scale>\n\n<!-- Quote.Total_With_VAT__c -->\n<fullName>Total_With_VAT__c</fullName>\n<formula>TotalPrice + Total_Tax__c</formula>\n<type>Currency</type>';
e4.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e4c1 };
entries.add(e4);

// ===== 5. Browse Catalog Sync Engineering =====
NotionPublishService.StarEntry e5 = new NotionPublishService.StarEntry();
e5.title = '5. Browse Catalog Sync Engineering — 4 Discovered Mechanisms';
e5.situation = 'Products created via Apex or REST never appeared in Browse Catalog UI even after Save and refresh. No clear Salesforce documentation on what triggers Browse Catalog visibility — wasted hours guessing. Demo blocked until products show up in the right account context.';
e5.taskText = 'Reverse-engineer the full sync pipeline from Product2 record creation to Browse Catalog visibility so changes propagate reliably and the pattern is documentable.';
e5.actions = new List<String>{
    'Discovered 4 required sync steps in order: (1) ProcedurePlanOption record per product+catalog, (2) Catalog publish via REST, (3) Product Discovery Index rebuild, (4) Salesforce Pricing Setup Sync',
    'Diagnosed Type field gotcha — Product2.Type must be NULL not "Base" or product is invisible; Type is not writeable on update so fix is recreate',
    'Found ProcedurePlanOption is what gates product entry into Pricing Procedure — without it, product exists but is unpriceable',
    'Wrote setup_workstation_catalog.apex automating all 4 sync steps with proper sequencing and wait/poll for index status',
    'Documented findings in browse_catalog_root_cause.md memory — Product Qualification procedure also blocks browse, must delete ProcedurePlanOption to unblock'
};
e5.result = 'Repeatable catalog setup script. Hamburg sees expected workstation tiers in <30 seconds after running setup. No more guess-and-check. Pattern now reusable for any new product category — POS, Cables, Software Licenses.';
NotionPublishService.CodeSnippet e5c1 = new NotionPublishService.CodeSnippet();
e5c1.caption = 'Catalog sync invocation order';
e5c1.language = 'java';
e5c1.code = '// 1. Insert ProcedurePlanOption per product\nList<ProcedurePlanOption> ppos = new List<ProcedurePlanOption>();\nfor (Product2 p : products) {\n    ppos.add(new ProcedurePlanOption(\n        ProductId = p.Id,\n        ProcedurePlanId = ppId\n    ));\n}\ninsert ppos;\n\n// 2. Publish catalog (REST callout)\n// 3. Trigger Product Discovery Index rebuild via Setup UI or API\n// 4. Run Salesforce Pricing Setup Sync\n// All 4 needed BEFORE product appears in Browse Catalog';
e5.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e5c1 };
entries.add(e5);

// ===== 6. Branded Contract PDF Auto-Generation =====
NotionPublishService.StarEntry e6 = new NotionPublishService.StarEntry();
e6.title = '6. Branded Contract PDF Auto-Generation';
e6.situation = 'TechnoStore stakeholders wanted branded contract PDFs auto-generated when a Contract is created — not requiring sales reps to manually click Generate Document. Native CLM document generation requires the manual Generate Document button click on Contract layout. Need a parallel system that fires on Contract Create.';
e6.taskText = 'Build Apex-driven PDF auto-attach on Contract Create alongside the native CLM template system so both options coexist (custom PDF auto, CLM Word template manual).';
e6.actions = new List<String>{
    'Built Visualforce page TechnoStoreContractPdf with renderAs="PDF" and Flying Saucer renderer for stable rendering',
    'Created ContractPdfController.cls calling Blob.toPdf() on the VF page via getContent()',
    'Wired ContractTriggerHandler.afterInsert to attach generated PDF as ContentVersion linked to Contract',
    'Hit Flying Saucer unicode gotcha — could not render lightning bolt char (TechnoStore logo had emoji), swapped to PNG logo asset',
    'Verified native CLM StandardContractTemplate (DocumentTemplate with UsageType=Contract_Lifecycle_Management) still works for manual generation — two parallel systems intentional'
};
e6.result = 'Every new Contract auto-receives branded PDF within seconds of creation. Sales reps see attached PDF on Contract page layout immediately. CLM native Generate Document available as second template option. Dual contract PDF system documented in dual_contract_pdf_systems.md memory.';
NotionPublishService.CodeSnippet e6c1 = new NotionPublishService.CodeSnippet();
e6c1.caption = 'ContractPdfController + trigger attach';
e6c1.language = 'java';
e6c1.code = 'public class ContractPdfController {\n    public Contract contract { get; set; }\n    public ContractPdfController() {\n        Id cId = ApexPages.currentPage().getParameters().get(\'id\');\n        contract = [SELECT Id, ContractNumber, AccountId\n                    FROM Contract WHERE Id = :cId LIMIT 1];\n    }\n}\n\n// In ContractTriggerHandler.afterInsert():\nPageReference pdfPage = Page.TechnoStoreContractPdf;\npdfPage.getParameters().put(\'id\', contract.Id);\nBlob pdfBlob = pdfPage.getContentAsPDF();\nContentVersion cv = new ContentVersion(\n    Title = \'TechnoStore Contract \' + contract.ContractNumber,\n    PathOnClient = \'contract.pdf\',\n    VersionData = pdfBlob,\n    FirstPublishLocationId = contract.Id\n);\ninsert cv;';
e6.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e6c1 };
entries.add(e6);

// ===== 7. CLM Submit for Approval — Custom Screen Flow =====
NotionPublishService.StarEntry e7 = new NotionPublishService.StarEntry();
e7.title = '7. CLM Submit for Approval — Custom Screen Flow Replacement';
e7.situation = 'Native CLM Submit for Approval button errored with TWO contradictory messages from the same broken control: "no approval process found" + "action isn\'t associated with state transition". Salesforce CLM Standard lifecycle actions are fragile in Dev Edition. Manager review step blocked.';
e7.taskText = 'Replace the broken native button with a working custom screen flow that submits Contract to manager approval reliably and integrates cleanly with Contract.Status state machine.';
e7.actions = new List<String>{
    'Built Submit_Contract_For_Approval screen flow — collects approver, sets Contract.Status to In Review, fires Approval Process',
    'Created Submit_For_Approval_Custom quick action on Contract layout (with Contract. prefix per platformActionList requirement)',
    'Configured Approval Process targeting Manager_Profile__c custom field for approval routing',
    'Removed native broken Submit button from Contract layout — separation of working vs broken UI clear',
    'Tested round-trip: Submit → manager approves → Status flips to Approved → next step (Sign) becomes available'
};
e7.result = 'Submit button on Contract works reliably. Approval routes to Manager_Profile__c user. Approver sees in Salesforce Approval queue. On approval, Contract.Status moves to Approved enabling downstream Sign + Activate flows. Pattern documented in clm_submit_for_approval_error.md memory.';
NotionPublishService.CodeSnippet e7c1 = new NotionPublishService.CodeSnippet();
e7c1.caption = 'Quick action + flow trigger pattern';
e7c1.language = 'xml';
e7c1.code = '<!-- platformActionList in Contract page layout -->\n<platformActionList>\n    <actionListContext>RecordHighlights</actionListContext>\n    <platformActionListItems>\n        <actionName>Contract.Submit_For_Approval_Custom</actionName>\n        <actionType>QuickAction</actionType>\n        <sortOrder>0</sortOrder>\n    </platformActionListItems>\n</platformActionList>\n\n<!-- Flow start: collect approver, then Approval action -->\n<actionCalls>\n    <name>Submit_To_Approval_Process</name>\n    <actionName>Submit_Contract_Approval</actionName>\n    <actionType>submit</actionType>\n</actionCalls>';
e7.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e7c1 };
entries.add(e7);

// ===== Publish all =====
Integer success = 0;
Integer failed = 0;
List<String> failures = new List<String>();
for (Integer i = 0; i < entries.size(); i++) {
    NotionPublishService.StarEntry e = entries.get(i);
    try {
        String pageId = NotionPublishService.publish(e);
        System.debug('✅ [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' → ' + pageId);
        success++;
    } catch (Exception ex) {
        System.debug('❌ [' + (i+1) + '/' + entries.size() + '] ' + e.title + ' — ' + ex.getMessage());
        failed++;
        failures.add(e.title + ': ' + ex.getMessage());
    }
}
System.debug('=== BATCH 1 COMPLETE === Success: ' + success + ' / Failed: ' + failed);
for (String f : failures) System.debug('FAIL: ' + f);
