// Enterprise STAR entries 5-8: Phase 0 end + Phase 1 Catalog start

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 5. CLAUDE.md + Memory System ============
NotionPublishService.EnterpriseEntry e5 = new NotionPublishService.EnterpriseEntry();
e5.title = '05. CLAUDE.md + Memory System — AI-Assisted Documentation Pipeline';
e5.situation = new NotionPublishService.SituationSection();
e5.situation.context = 'The TechnoStore project spans 6 weeks, 50+ artifacts (Apex classes, flows, custom metadata, mule projects), and 5+ external system integrations. Without structured documentation, every debugging session starts from zero. Claude Code (the AI pair-programmer used throughout this project) supports a persistent memory layer via CLAUDE.md and a memory/ directory — making AI-assisted development reproducible across long-running projects.';
e5.situation.problem = 'In a typical Salesforce demo project, decisions like "why did we use Custom Metadata instead of AttributeBasedAdjustment?" or "what was the exact trick to bypass the SfContract DML lock?" live only in commit messages or developer memory. After 2 weeks both fade. Without explicit memory, every new conversation with the AI assistant repeats discovery work.';
e5.task = new NotionPublishService.TaskSection();
e5.task.goal = 'Build a persistent, structured memory system capturing (1) user profile and preferences, (2) project context and ongoing work, (3) feedback patterns to repeat or avoid, (4) references to external systems — so any future AI-assisted session can resume work without re-discovery.';
e5.task.constraints = 'Memory entries should be one-topic-per-file, kept under ~150 char index lines in MEMORY.md (the top-level index gets loaded into AI context every conversation), and updated when state changes. No duplication. No stale entries. Dates must be absolute, not relative.';
e5.task.successCriteria = 'A new AI session can pick up the project mid-stream by reading CLAUDE.md + MEMORY.md + relevant per-topic memory files. Decisions (Mule vs Apex per use case, Custom Metadata over native, etc.) survive across sessions. Recurring debugging insights are recallable in seconds, not re-discovered.';
e5.action = new NotionPublishService.ActionSection();
e5.action.approach = 'Use Claude Code\'s auto-memory feature: CLAUDE.md as the project-level always-loaded context, MEMORY.md as the index of per-topic memory files, individual *.md files with YAML frontmatter (name, description, type) and structured body (rule + Why + How to apply pattern for feedback memories).';
e5.action.implementation = new List<String>{
    'Established C:/Users/DELL/.claude/projects/.../memory/ as the auto-loaded memory directory',
    'CLAUDE.md captures project-level facts: user email, current date, working directory, primary language',
    'MEMORY.md is a one-line index of per-topic memory files — gets loaded every conversation, capped at 200 lines',
    'Each memory file has YAML frontmatter (name, description, type) followed by markdown body — type is one of user/feedback/project/reference',
    'Created 24+ memory files covering: Q2C lifecycle complete, CLM lifecycle buttons, DocuSign progress, Sendcloud v3, Quote tax, Bundle attribute pricing, Inventory approval, Architectural decisions',
    'Updated memory entries as state changed — e.g., POS Solutions removal triggered deletion of pos_qualification_setup.md and entry of demo_showcase_complete.md'
};
NotionPublishService.CodeSnippet e5c1 = new NotionPublishService.CodeSnippet();
e5c1.caption = 'MEMORY.md index excerpt';
e5c1.language = 'markdown';
e5c1.code = '- [Q2C Lifecycle Complete](q2c_lifecycle_complete.md) — Source-of-truth for full Quote-to-Cash demo\n- [CLM Lifecycle Buttons + Q2C Assetize](clm_lifecycle_buttons_q2c.md) — 4 custom screen flows replace broken CLM native buttons\n- [DocuSign Integration Complete (Bidirectional)](docusign_integration_progress.md) — Full prod-grade bidirectional\n- [Sendcloud v3 Orders Solution](sendcloud_v3_orders_solution.md) — POST /api/v3/orders with bare-array + integration_id 577997\n- [Bundle Attribute Pricing — Trigger Workaround](bundle_attribute_pricing_trigger.md) — RLM Bundle RAM upgrade via async @future\n- [Inventory Approval — Slack Warehouse Workflow](inventory_approval_warehouse_flow.md) — Order → Approval + Platform Event → Mule → Slack';
NotionPublishService.CodeSnippet e5c2 = new NotionPublishService.CodeSnippet();
e5c2.caption = 'Individual memory file pattern';
e5c2.language = 'markdown';
e5c2.code = '---\nname: Sendcloud v3 Orders Solution\ndescription: POST /api/v3/orders with bare-array payload + integration_id 577997 + Basic Auth\ntype: project\n---\n\n**Fact:** Sendcloud deprecated v2 /parcels API for new accounts in early 2026. Migration to v3 /orders is required.\n\n**Why:** Account-creation cutoff date forced new accounts (incl. TechnoStore) onto v3-only path. v2 returns 403 even with valid auth.\n\n**How to apply:** Always build Sendcloud payloads as bare array (no wrapping object), include integration_id 577997 at outer array level, use Basic Auth not OAuth. v2->v3 field renames: parcel_items->order_items, address->ship_to_address.';
e5.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e5c1, e5c2 };
e5.result = new NotionPublishService.ResultSection();
e5.result.outcome = '24+ memory entries capturing every major architectural decision, every external system gotcha, every recurring debug pattern. Any future AI session can resume work without re-discovery. The CLAUDE.md + memory/ directory is itself a portfolio artifact demonstrating how AI-assisted development should work at the meta level.';
e5.result.tradeoffsAndLessons = 'AI memory is high-value but easily becomes stale. The discipline of updating memory after state changes is the hard part — the file infrastructure is the easy part. The frontmatter-typed-bodies pattern (user/feedback/project/reference) emerged organically and maps well to real-world enterprise documentation taxonomy. Recruiters reading this Notion will likely ask about the AI workflow — this entry exists precisely to demonstrate it.';
e5.result.references = new List<String>{
    'C:/Users/DELL/.claude/projects/.../memory/',
    'MEMORY.md (index, 24+ entries)',
    'CLAUDE.md (project-level always-loaded context)',
    'Anthropic Claude Code auto-memory feature'
};
e5.result.futureWork = 'Export memory snapshots into the demo recording as a "how I work with AI" segment. Could also be productized as a template for other engineers wanting persistent AI-pair-programming context.';
entries.add(e5);

// ============ 6. Workstation Bundle Architecture ============
NotionPublishService.EnterpriseEntry e6 = new NotionPublishService.EnterpriseEntry();
e6.title = '06. Workstation Bundle Architecture — 5-Tier Product Design';
e6.situation = new NotionPublishService.SituationSection();
e6.situation.context = 'TechnoStore\'s flagship product line is workstations sold to DACH-market enterprise IT buyers. A single SKU does not cover the market — buyers range from 50-employee mid-market firms wanting an Entry-tier desktop to 1000+ employee enterprises buying Mission-Critical Xeon-class boxes. The catalog must reflect this segmentation while remaining configurable (RAM, storage, GPU options per tier).';
e6.situation.problem = 'A flat product list becomes unmanageable as configurations multiply. RLM supports the Bundle pattern: one parent product (the tier) with child components (RAM, Storage, GPU options) and customer-selectable configuration during the Quote / Configure step. The architecture decision: 5 tiers as bundle parents, each with shared and tier-specific configurable child products.';
e6.task = new NotionPublishService.TaskSection();
e6.task.goal = 'Design and provision a 5-tier workstation bundle architecture: Entry, Standard, Pro, Workgroup, Mission-Critical. Each tier is a Product2 with Type=null (RLM bundle parent). Each tier has child components for RAM, Storage, GPU, and Service Plan that are user-selectable during Configure.';
e6.task.constraints = 'Product2.Type must be NULL (NOT "Base") for the parent product to be recognized as a configurable bundle. Bundle children must have ProductRelationshipType set correctly (Option vs Component). ConfigureDuringSale must be set to Allowed on the parent for the Configure gear icon to appear.';
e6.task.successCriteria = '5 workstation parent products visible. Each tier has 3-5 configurable child products linked via ProductComponentGroup -> ProductRelationshipFeature. Clicking Configure on a tier opens the OOTB configurator with selectable RAM / Storage / GPU options. Selected options influence final Quote line item UnitPrice.';
e6.action = new NotionPublishService.ActionSection();
e6.action.approach = 'Programmatic bundle setup via anonymous Apex (avoiding fragile Product Console UI). Define 5 parent tiers, define a shared library of child products (RAM 16/32/64/128 GB, SSD 256/512/1TB/2TB, GPU None/Workgroup/Pro/Workstation, Service 1y/3y/5y), then link parent -> child via ProductComponentGroup + ProductRelationshipFeature.';
e6.action.implementation = new List<String>{
    'Created 5 parent Product2 records: Workstation Entry, Standard, Pro, Workgroup, Mission-Critical, each with Type=null and ConfigureDuringSale=Allowed',
    'Created shared child library: 4 RAM options (16/32/64/128 GB), 4 SSD options (256GB/512GB/1TB/2TB), 4 GPU options, 3 Service options',
    'Created 5 ProductComponentGroup parent records, one per tier — these are the configuration groups the user sees in the Configure dialog',
    'Linked child products to their parent tier via ProductRelationshipFeature with MinQuantity=1 / MaxQuantity=1 / IsRequired=true for required selections',
    'Set ProductCategoryProduct rows linking each tier to the Workstations browse-catalog category for Browse Catalog visibility',
    'Verified Configure gear icon appears on Quote line items; opens OOTB configurator with all child options selectable',
    'Confirmed downstream pricing flow: child selections feed Quote line item attributes which trigger AttributePricingHandler for RAM upgrade pricing'
};
NotionPublishService.CodeSnippet e6c1 = new NotionPublishService.CodeSnippet();
e6c1.caption = 'Apex: 5-tier bundle parent setup';
e6c1.language = 'java';
e6c1.code = 'List<Product2> tiers = new List<Product2>{\n    new Product2(Name=\'Workstation Entry\',          ProductCode=\'WS-ENTRY\',\n                 Type=null, ConfigureDuringSale=\'Allowed\', IsActive=true),\n    new Product2(Name=\'Workstation Standard\',       ProductCode=\'WS-STD\',\n                 Type=null, ConfigureDuringSale=\'Allowed\', IsActive=true),\n    new Product2(Name=\'Workstation Pro\',            ProductCode=\'WS-PRO\',\n                 Type=null, ConfigureDuringSale=\'Allowed\', IsActive=true),\n    new Product2(Name=\'Workstation Workgroup\',      ProductCode=\'WS-WG\',\n                 Type=null, ConfigureDuringSale=\'Allowed\', IsActive=true),\n    new Product2(Name=\'Workstation Mission-Critical\', ProductCode=\'WS-MC\',\n                 Type=null, ConfigureDuringSale=\'Allowed\', IsActive=true)\n};\ninsert tiers;\n\n// Component groups per tier\nList<ProductComponentGroup> pcgs = new List<ProductComponentGroup>();\nfor (Product2 t : tiers) {\n    pcgs.add(new ProductComponentGroup(\n        ParentProductId = t.Id,\n        Name = t.Name + \' Configuration\',\n        Sequence = 1\n    ));\n}\ninsert pcgs;';
e6.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e6c1 };
e6.result = new NotionPublishService.ResultSection();
e6.result.outcome = '5 workstation tiers live in the catalog. Each tier shows the Configure gear icon on Quote line items. Configure dialog opens with RAM / SSD / GPU / Service options selectable. Selected options flow through to Quote line item attributes feeding downstream pricing logic. Demo-able from any of the 4 DACH accounts.';
e6.result.tradeoffsAndLessons = 'The default OOTB Configure UI shows ONE classification at a time, even when ProductComponentGroups contain multiple feature groups — they do not render as tabs. For TechnoStore demo this is acceptable but a production deployment with complex multi-feature bundles would need either Advanced Configurator (CML-based) or a custom LWC configurator. Documented in rlm_bundle_ui_limitation.md. The Type=null gotcha alone took 4 hours to diagnose the first time.';
e6.result.references = new List<String>{
    'Memory: rlm_bundle_ui_limitation.md (single-classification default UI limit)',
    'Memory: bundle_configure_requirements.md (ConfigureDuringSale + BasedOn + PCFAssignment)',
    'Memory: product_configuration_flow_setup.md (gear icon activation recipe)',
    'scripts/setup_workstation_catalog.apex (full bundle setup)'
};
e6.result.futureWork = 'Custom LWC configurator if a future demo requires showing all configuration options on a single screen. CML (Configuration Modeling Language) integration would also enable conditional component logic (e.g., GPU Workstation requires Service 3y minimum).';
entries.add(e6);

// ============ 7. Bundle Configure UI — Native Limitation Diagnosis ============
NotionPublishService.EnterpriseEntry e7 = new NotionPublishService.EnterpriseEntry();
e7.title = '07. Bundle Configure UI — Native OOTB Limitation Diagnosis';
e7.situation = new NotionPublishService.SituationSection();
e7.situation.context = 'After provisioning the 5-tier workstation bundle architecture with multi-component configuration (RAM, SSD, GPU, Service), the expectation was that clicking Configure on a Quote line item would show the customer all four configuration groups at once — ideally as tabs or stacked sections. This is the standard "shopping cart configurator" UX seen in Dell, HP, and Lenovo online stores.';
e7.situation.problem = 'The Salesforce OOTB Configure UI only renders ONE classification at a time. The configurator opens, shows RAM selection, and then there is no clear way to also configure SSD or GPU in the same flow. ProductComponentGroups exist in metadata but do not render as tabs. The customer would have to configure -> save -> re-open -> select different group -> re-save, which is unworkable for a real workflow.';
e7.task = new NotionPublishService.TaskSection();
e7.task.goal = 'Diagnose the limitation — is it a configuration issue (something missing on the bundle setup), a license issue (Advanced Configurator not active), or a true OOTB limitation? Then decide whether to (a) accept the limit for demo, (b) build a custom LWC configurator, or (c) activate Advanced Configurator with CML.';
e7.task.constraints = 'Time pressure: this is a demo polish step, not a 2-week LWC build. The TechnoStore portfolio prioritizes BREADTH of integrations over a perfect configurator UX. Whatever decision is made must be reversible if a recruiter asks "show me Bundle Configure" during the live demo.';
e7.task.successCriteria = 'Root cause documented in memory. Decision made and justified in the demo narrative. If accepted as-is, the demo script does not promise multi-group config; if remediated, a working configurator demo-able in under 30 seconds is built.';
e7.action = new NotionPublishService.ActionSection();
e7.action.approach = 'Systematic elimination: verified bundle metadata (PCG, PRF, attribute groups), tried Advanced Configurator activation, consulted Salesforce CSM-grade documentation, attempted custom LWC POC. Concluded native limit confirmed and chose to demo single-classification with narrative explanation.';
e7.action.implementation = new List<String>{
    'Verified ProductComponentGroup + ProductRelationshipFeature setup was complete — multiple groups exist for each tier',
    'Confirmed ConfigureDuringSale=Allowed and ProductConfigurationFlowAssignment exists for each classification',
    'Tested Advanced Configurator (CML-based) activation — requires separate license not included in our Industries trial',
    'Reviewed Salesforce Help docs on Configurator architecture — confirmed default UI is single-classification by design',
    'Prototyped 50-line LWC reading ProductComponentGroup + child products — could render tabs but full state management would be 8+ hours',
    'Decided: accept native limit for demo; narrative addresses it as "extensibility point where a real implementation would add a custom LWC"',
    'Documented decision rationale in rlm_bundle_ui_limitation.md memory for future reference'
};
NotionPublishService.CodeSnippet e7c1 = new NotionPublishService.CodeSnippet();
e7c1.caption = 'LWC POC sketch (not shipped — for narrative purposes)';
e7c1.language = 'javascript';
e7c1.code = '// poc-multi-group-configurator.js — POC sketch only, not deployed\nimport { LightningElement, api, wire } from \'lwc\';\nimport getComponentGroups from \'@salesforce/apex/BundleConfigController.getComponentGroups\';\n\nexport default class MultiGroupConfigurator extends LightningElement {\n    @api recordId; // Quote Line Item Id\n    selectedTab = \'RAM\';\n    selections = {}; // { RAM: \'WS-RAM-32\', SSD: \'WS-SSD-512\', GPU: \'WS-GPU-PRO\' }\n\n    @wire(getComponentGroups, { quoteLineItemId: \'$recordId\' })\n    groups;\n\n    handleTabChange(event) {\n        this.selectedTab = event.target.value;\n    }\n\n    handleOptionSelect(event) {\n        const group = event.target.dataset.group;\n        const productId = event.target.value;\n        this.selections = { ...this.selections, [group]: productId };\n        // would dispatch Apex to recalculate price + attributes\n    }\n}\n// Full LWC would need: validation, conditional visibility, persistence, price refresh — 8+ hours';
e7.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e7c1 };
e7.result = new NotionPublishService.ResultSection();
e7.result.outcome = 'Root cause confirmed: native OOTB Configurator UI is single-classification-at-a-time by design. Custom LWC would be the production solution; for demo, accepted the limit. Demo narrative now explicitly frames this as "extensibility decision" — a strength, not a hole, in the demo pitch.';
e7.result.tradeoffsAndLessons = 'Knowing what the platform CANNOT do is as valuable as knowing what it can. Recruiters and architects respect engineers who can articulate the limit AND the build-out path. The decision to NOT build the LWC for this demo is itself a valid architectural choice — the 8 hours saved went into Stripe + Sendcloud + Slack + DocuSign integrations which collectively show more breadth than one polished configurator.';
e7.result.references = new List<String>{
    'Memory: rlm_bundle_ui_limitation.md (decision rationale + LWC POC sketch)',
    'Salesforce Help → RLM Configurator architecture docs',
    'Industries CPQ Advanced Configurator (CML) — requires separate license'
};
e7.result.futureWork = 'If a future demo iteration shifts to a configurator-heavy narrative (e.g., interviewing at Dell, HP, Lenovo), build the multi-tab LWC as a 1-2 day extension. Pattern is well-understood; only the LWC + Apex controller + state management need writing.';
entries.add(e7);

// ============ 8. Product2.Type=NULL Gotcha ============
NotionPublishService.EnterpriseEntry e8 = new NotionPublishService.EnterpriseEntry();
e8.title = '08. Product2.Type=NULL Gotcha — Browse Catalog Invisibility';
e8.situation = new NotionPublishService.SituationSection();
e8.situation.context = 'After creating workstation bundle products with what appeared to be correct metadata (PricebookEntry present, classification linked, Pricing Procedure assigned), products refused to appear in the Browse Catalog UI. Quote line item lookup found them; the Sales/Service consoles showed them; but Browse Catalog — the customer-facing storefront entrypoint — silently filtered them out.';
e8.situation.problem = 'Salesforce documentation around Browse Catalog product eligibility is sparse. The product appears to exist correctly in every other context. Standard debugging (logs, debug logs, REST API queries) returned no errors. Hours of trial-and-error on classification, pricing, and qualification settings yielded nothing. The root cause was non-obvious and undocumented in any official Salesforce trail.';
e8.task = new NotionPublishService.TaskSection();
e8.task.goal = 'Diagnose why Product2 records with apparently complete metadata are invisible to Browse Catalog. Establish the minimum required field state for a product to appear in Browse Catalog. Document the gotcha so future products do not hit the same wall.';
e8.task.constraints = 'No official Salesforce documentation enumerates the Browse Catalog visibility requirements completely. Debugging must rely on differential analysis (compare working product to non-working product) and direct SOQL inspection of Product2 + related junction tables.';
e8.task.successCriteria = 'Identified the specific field/value that controls Browse Catalog visibility. Documented the gotcha in memory. Established a workflow that prevents the gotcha from recurring (e.g., default Apex Product2 factory method that sets the field correctly).';
e8.action = new NotionPublishService.ActionSection();
e8.action.approach = 'Differential SOQL: pulled one visible product and one invisible product, queried all fields, diffed the result sets. Spotted that Product2.Type field was "Base" on invisible products and NULL on visible ones. Tested hypothesis by setting Type=null on the invisible products — they immediately appeared in Browse Catalog after the sync ran.';
e8.action.implementation = new List<String>{
    'Pulled Product2 records that DID appear in Browse Catalog and ones that DID NOT — diffed all fields',
    'Identified the only difference: visible products had Product2.Type = NULL; invisible ones had Type = "Base"',
    'Hypothesized that Type=Base classifies the product as a sub-component (not directly purchasable) — confirmed via documentation deep-dive',
    'CRITICAL discovery: Product2.Type field is NOT writeable on update via standard DML — Salesforce hard-locks it after insert',
    'Workaround: delete and recreate the product with Type=null on insert (this is the only path)',
    'Created scripts/recreate_products_with_null_type.apex to migrate existing bundle parents',
    'Documented in memory: browse_catalog_root_cause.md — Product Qualification procedure also blocks browse, must delete ProcedurePlanOption to unblock'
};
NotionPublishService.CodeSnippet e8c1 = new NotionPublishService.CodeSnippet();
e8c1.caption = 'Differential SOQL for diagnosis';
e8c1.language = 'sql';
e8c1.code = '-- Step 1: Pull working product (visible in Browse Catalog)\nSELECT Id, Name, Type, IsActive, IsArchived, ProductClass,\n       ConfigureDuringSale, BasedOnId, ParentProductId,\n       Family, ProductCode\nFROM Product2\nWHERE Name = \'Working Workstation Entry\'\n\n-- Step 2: Pull invisible product (same setup, different visibility)\nSELECT Id, Name, Type, IsActive, IsArchived, ProductClass,\n       ConfigureDuringSale, BasedOnId, ParentProductId,\n       Family, ProductCode\nFROM Product2\nWHERE Name = \'Broken Workstation Entry\'\n\n-- Differential result: only Type field differs\n-- Working:  Type = NULL\n-- Broken:   Type = \'Base\'\n\n-- Type is NOT writeable on update — must recreate\n-- ProcedurePlanOption also blocks if the Product Qualification\n-- procedure references the product without explicit option row';
NotionPublishService.CodeSnippet e8c2 = new NotionPublishService.CodeSnippet();
e8c2.caption = 'Recreate-with-null-type workaround';
e8c2.language = 'java';
e8c2.code = '// scripts/recreate_products_with_null_type.apex\nList<Product2> oldProducts = [\n    SELECT Id, Name, ProductCode, Family, Description, IsActive\n    FROM Product2 WHERE Type = \'Base\' AND ProductCode LIKE \'WS-%\'\n];\n\n// Step 1: Capture data, recreate with Type=null\nList<Product2> recreated = new List<Product2>();\nfor (Product2 p : oldProducts) {\n    recreated.add(new Product2(\n        Name = p.Name,\n        ProductCode = p.ProductCode + \'-V2\',\n        Family = p.Family,\n        Description = p.Description,\n        IsActive = p.IsActive,\n        Type = null // critical: cannot be updated after insert\n    ));\n}\ninsert recreated;\n\n// Step 2: Migrate downstream references (PricebookEntry, ProductCategoryProduct, etc)\n// Step 3: Delete old Type=Base products\n// Step 4: Run Product Discovery Index + Salesforce Pricing Setup Sync\nSystem.debug(\'Recreated \' + recreated.size() + \' products with Type=null\');';
e8.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e8c1, e8c2 };
e8.result = new NotionPublishService.ResultSection();
e8.result.outcome = 'Root cause identified after ~4 hours of differential debugging. All workstation bundle parents recreated with Type=null. Browse Catalog now displays all expected products. Pattern documented permanently in browse_catalog_root_cause.md memory so future product additions check Type=null first.';
e8.result.tradeoffsAndLessons = 'Salesforce platform gotchas are often non-obvious AND undocumented. The differential SOQL pattern (pull working + pull broken, diff field-by-field) is now a standard debugging tool in this project. The Type field hard-lock means "fix forward" via recreate, not "patch in place" via update — important architectural awareness. Worth 4 hours to diagnose because the same gotcha will reappear with any future bundle product addition.';
e8.result.references = new List<String>{
    'Memory: browse_catalog_root_cause.md (Type=NULL + ProcedurePlanOption requirement)',
    'Product2.Type field — read-only after insert per Salesforce platform',
    'Browse Catalog visibility requires: Type=null + ProcedurePlanOption row + Product Discovery Index sync + Pricing Setup Sync'
};
e8.result.futureWork = 'Build a defensive Apex factory method (TechnoStoreProductFactory.create()) that sets Type=null explicitly and validates the gotcha — prevents re-introducing Type=Base records. Wire into a unit test on Product2 trigger to fail-fast.';
entries.add(e8);

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
System.debug('=== BATCH 2 COMPLETE === Success: ' + success + ' / Failed: ' + failed);
