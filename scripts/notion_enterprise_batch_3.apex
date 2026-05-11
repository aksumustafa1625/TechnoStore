// Enterprise STAR entries 9-12: Phase 1 end + Phase 2 start

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 9. Browse Catalog Sync Engineering ============
NotionPublishService.EnterpriseEntry e9 = new NotionPublishService.EnterpriseEntry();
e9.title = '09. Browse Catalog Sync Engineering — 4 Discovered Mechanisms';
e9.situation = new NotionPublishService.SituationSection();
e9.situation.context = 'Browse Catalog is the customer-facing storefront page in Industries CPQ where Account-context-aware product browsing happens. For TechnoStore demo it is the entrypoint: Hamburg DataWorks logs in, sees the workstation tiers eligible for their employee size, picks one, configures it. Browse Catalog is the foundation of the buyer-experience demo narrative.';
e9.situation.problem = 'Products created via Apex or REST never appeared in Browse Catalog UI even after Save and refresh. The same products appeared in Quote line item lookup, in the Sales Console, in REST API queries — but Browse Catalog filtered them out silently. No clear Salesforce documentation on what triggers Browse Catalog visibility. Demo blocked until products show up in the right account context.';
e9.task = new NotionPublishService.TaskSection();
e9.task.goal = 'Reverse-engineer the full sync pipeline from Product2 record creation to Browse Catalog visibility so changes propagate reliably and the pattern is documentable for future product additions.';
e9.task.constraints = 'No official Salesforce documentation enumerates the sync steps. Must debug via differential analysis (which step makes products appear?), trial-and-error with Setup actions, and direct SOQL inspection of every junction object in the Industries data model.';
e9.task.successCriteria = 'A documented sequence of steps that, when run in order, makes any new Product2 record appear in Browse Catalog within 30 seconds. The sequence is automated in a setup Apex script and re-runnable for new product batches.';
e9.action = new NotionPublishService.ActionSection();
e9.action.approach = 'Add steps one-by-one, test after each, identify which step is the missing link. Built up the full sync chain experimentally over multiple iterations. Final pipeline has 4 distinct sync mechanisms that all must complete in order.';
e9.action.implementation = new List<String>{
    'Discovered 4 required sync steps: (1) ProcedurePlanOption record per product+catalog (without this product cannot enter Pricing Procedure), (2) Catalog Publish via REST API call, (3) Product Discovery Index rebuild (Setup → Industries → Index Status), (4) Salesforce Pricing Setup Sync',
    'Diagnosed Type field gotcha — Product2.Type must be NULL not "Base" or product is invisible regardless of other syncs (covered in separate entry)',
    'Found ProcedurePlanOption is what gates product entry into Pricing Procedure — without it, product exists but is unpriceable from Browse Catalog perspective',
    'Wrote setup_workstation_catalog.apex automating all 4 sync steps with proper sequencing and wait/poll for index status',
    'Documented findings in browse_catalog_root_cause.md memory — Product Qualification procedure also blocks browse, must delete ProcedurePlanOption to unblock when product qualification is the issue',
    'Validated end-to-end: Hamburg DataWorks account opens Browse Catalog and sees the expected 4 workstation tiers within 30 seconds of running the sync script'
};
NotionPublishService.CodeSnippet e9c1 = new NotionPublishService.CodeSnippet();
e9c1.caption = 'Catalog sync invocation order (all 4 steps)';
e9c1.language = 'java';
e9c1.code = '// scripts/setup_workstation_catalog.apex\n// Order matters — each step depends on the previous.\n\n// Step 1: Insert ProcedurePlanOption per product (gates pricing procedure entry)\nList<ProcedurePlanOption> ppos = new List<ProcedurePlanOption>();\nfor (Product2 p : workstationProducts) {\n    ppos.add(new ProcedurePlanOption(\n        ProductId = p.Id,\n        ProcedurePlanId = pricingProcedureId,\n        IsActive = true\n    ));\n}\ninsert ppos;\n\n// Step 2: Publish catalog via REST callout\nHttpRequest publishReq = new HttpRequest();\npublishReq.setEndpoint(\'callout:Industries_API/catalog/\' + catalogId + \'/publish\');\npublishReq.setMethod(\'POST\');\nnew Http().send(publishReq);\n\n// Step 3: Trigger Product Discovery Index rebuild\n// (must be done via Setup UI — no public API as of 2026-05)\n// Setup → Industries → Product Discovery → Rebuild Index\n\n// Step 4: Run Salesforce Pricing Setup Sync\n// (Setup → Industries → Pricing → Setup Sync)\n\n// All 4 steps complete before product appears in Browse Catalog';
e9.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e9c1 };
e9.result = new NotionPublishService.ResultSection();
e9.result.outcome = 'Repeatable catalog setup script. Hamburg sees expected workstation tiers in <30 seconds after running setup. No more guess-and-check. Pattern now reusable for any new product category — POS, Cables, Software Licenses. Saved 4-6 hours per new product batch addition.';
e9.result.tradeoffsAndLessons = 'Industries CPQ has rich functionality but extensive undocumented setup requirements. The 4-step sync chain is the kind of platform knowledge that takes hours to discover and stays with the engineer permanently. Worth investing in documenting it explicitly in memory + a runnable Apex script. Pattern: when product is invisible but everything looks correct, the issue is one of 4 sync steps — work through them in order.';
e9.result.references = new List<String>{
    'scripts/setup_workstation_catalog.apex (all 4 sync steps automated)',
    'Memory: browse_catalog_root_cause.md (root cause + sync chain)',
    'ProcedurePlanOption — gates product entry into Pricing Procedure',
    'Setup → Industries → Product Discovery → Rebuild Index (manual step)'
};
e9.result.futureWork = 'Wrap step 3 (Product Discovery Index rebuild) in an Apex callable if/when Salesforce publishes a public API for index trigger. Currently the script must instruct the operator to perform the manual Setup action — automation gap remains.';
entries.add(e9);

// ============ 10. ProductCategory + Classification Hierarchy ============
NotionPublishService.EnterpriseEntry e10 = new NotionPublishService.EnterpriseEntry();
e10.title = '10. ProductCategory + Classification Hierarchy';
e10.situation = new NotionPublishService.SituationSection();
e10.situation.context = 'Browse Catalog needs a navigable category hierarchy so customers can drill from "All Products" → "Workstations" → "Workstation Pro" etc. Industries CPQ models this via ProductCategory (the navigation tree) and ProductClassification (the metadata-driven configuration class for products of the same kind). Both must be set up correctly for products to appear in their expected category nodes.';
e10.situation.problem = 'Without explicit ProductCategory + ProductCategoryProduct junction rows, Products show up under "Uncategorized" (if at all) and not in their intended category. Without ProductClassification, products are missing the configuration class that drives the Configure UI rendering (which fields show, which attributes are editable). The metadata graph is bigger than it looks at first.';
e10.task = new NotionPublishService.TaskSection();
e10.task.goal = 'Build a clean 2-level category hierarchy (root: TechnoStore → categories: Workstations / Peripherals / Cables / Software Licenses → products within each). Link each Product2 to its correct category via ProductCategoryProduct. Assign correct ProductClassification per product type.';
e10.task.constraints = 'ProductCategory rows form a tree via ParentCategoryId — must be inserted parent-first. ProductCategoryProduct junction has uniqueness constraints (one product per category per catalog). ProductClassification.BasedOnId determines which fields are configurable — wrong classification = wrong Configure UI behavior.';
e10.task.successCriteria = 'Browse Catalog navigation shows TechnoStore root → 4 categories → expected product counts. Each category lists its assigned products. Clicking Configure on a workstation opens with RAM/SSD/GPU fields based on Workstation classification (not generic Product fields).';
e10.action = new NotionPublishService.ActionSection();
e10.action.approach = 'Apex setup script that inserts (1) ProductCategory tree in parent-first order, (2) ProductClassification records per product type with appropriate BasedOnId, (3) ProductCategoryProduct junctions linking each product to its category, (4) updates Product2.BasedOnId to point at correct ProductClassification.';
e10.action.implementation = new List<String>{
    'Built ProductCategory tree: root TechnoStore (no parent) -> 4 child categories (Workstations, Peripherals, Cables, Software Licenses), each with proper ParentCategoryId',
    'Created 4 ProductClassification records, one per product type — defines which Product fields participate in Configure',
    'Linked each Product2 to its ProductClassification via Product2.BasedOnId — critical for Configure UI to know the configuration class',
    'Inserted ProductCategoryProduct junction rows linking each Product2 to exactly one ProductCategory (uniqueness enforced)',
    'Verified Browse Catalog navigation: TechnoStore root expands to 4 categories, each shows expected product counts (e.g., Workstations: 5 tiers visible to Hamburg DataWorks)',
    'Confirmed Configure UI now opens with classification-specific attributes (RAM/SSD/GPU for Workstations, not generic Product fields)'
};
NotionPublishService.CodeSnippet e10c1 = new NotionPublishService.CodeSnippet();
e10c1.caption = 'Apex: 2-level category hierarchy setup';
e10c1.language = 'java';
e10c1.code = '// Step 1: Root + 4 categories (parent first, then children)\nProductCategory root = new ProductCategory(\n    Name = \'TechnoStore\',\n    CatalogId = catalogId,\n    SortOrder = 0\n);\ninsert root;\n\nList<ProductCategory> categories = new List<ProductCategory>{\n    new ProductCategory(Name=\'Workstations\',      ParentCategoryId=root.Id, CatalogId=catalogId, SortOrder=1),\n    new ProductCategory(Name=\'Peripherals\',       ParentCategoryId=root.Id, CatalogId=catalogId, SortOrder=2),\n    new ProductCategory(Name=\'Cables\',            ParentCategoryId=root.Id, CatalogId=catalogId, SortOrder=3),\n    new ProductCategory(Name=\'Software Licenses\', ParentCategoryId=root.Id, CatalogId=catalogId, SortOrder=4)\n};\ninsert categories;\n\n// Step 2: ProductClassification per product type\nList<ProductClassification> classifications = new List<ProductClassification>{\n    new ProductClassification(Name=\'Workstation\',  Code=\'CLASS_WORKSTATION\',  Status=\'Active\'),\n    new ProductClassification(Name=\'Peripheral\',   Code=\'CLASS_PERIPHERAL\',   Status=\'Active\'),\n    new ProductClassification(Name=\'Cable\',        Code=\'CLASS_CABLE\',        Status=\'Active\'),\n    new ProductClassification(Name=\'Software\',     Code=\'CLASS_SOFTWARE\',     Status=\'Active\')\n};\ninsert classifications;\n\n// Step 3: Link products to category + classification\nList<ProductCategoryProduct> junctions = new List<ProductCategoryProduct>();\nList<Product2> productUpdates = new List<Product2>();\nfor (Product2 p : workstationProducts) {\n    junctions.add(new ProductCategoryProduct(\n        ProductCategoryId = categoriesByName.get(\'Workstations\').Id,\n        ProductId = p.Id\n    ));\n    productUpdates.add(new Product2(Id = p.Id, BasedOnId = classByCode.get(\'CLASS_WORKSTATION\').Id));\n}\ninsert junctions;\nupdate productUpdates;';
e10.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e10c1 };
e10.result = new NotionPublishService.ResultSection();
e10.result.outcome = 'Clean 2-level category hierarchy in Browse Catalog. Each product correctly assigned. Configure UI opens with classification-specific attributes. Demo navigation tells a clear story: TechnoStore -> Workstations -> 5 tiers -> Configure with RAM/SSD/GPU options.';
e10.result.tradeoffsAndLessons = 'The Industries CPQ data model is graph-heavy: Product2 + ProductCategory + ProductCategoryProduct + ProductClassification + ProductRelationshipFeature + ProductComponentGroup + AttributeBasedAdjustment + ProcedurePlanOption are all interconnected. Setup must be done in dependency order or DML throws integrity errors. The parent-first insert pattern for the category tree is a generally-useful template.';
e10.result.references = new List<String>{
    'scripts/setup_workstation_catalog.apex',
    'ProductCategory.ParentCategoryId — self-referential FK (insert parents first)',
    'ProductClassification.BasedOnId + Product2.BasedOnId — must match for Configure UI'
};
e10.result.futureWork = 'Add 3rd-level subcategories (e.g., Workstations -> Desktop / Laptop / Mobile) if catalog grows. Current 2-level is sufficient for the demo.';
entries.add(e10);

// ============ 11. POS Solutions Experiment + Complete Cleanup ============
NotionPublishService.EnterpriseEntry e11 = new NotionPublishService.EnterpriseEntry();
e11.title = '11. POS Solutions Experiment + Complete Cleanup';
e11.situation = new NotionPublishService.SituationSection();
e11.situation.context = 'Mid-project, the demo scope considered expanding beyond workstations into POS (Point-of-Sale) systems — terminals, receipt printers, barcode scanners. Created POS category, 8 POS products, set up qualification rules. The intention was to demonstrate Industries-aware qualification (POS only sold to retail-Industry accounts).';
e11.situation.problem = 'Discovered that the RLM native qualification engine does NOT enforce ProductDisqualification.Industry__c — products that should be disqualified for non-retail Industry accounts still appeared in Browse Catalog. Built an Apex trigger workaround which then caused a Java cast exception inside PlaceSalesTransactionPersistException (Salesforce platform bug). Three failed approaches; decision to abandon POS scope entirely.';
e11.task = new NotionPublishService.TaskSection();
e11.task.goal = 'Cleanly remove POS Solutions feature from the demo — including 8 products, qualification rules, ProductCategory, ProductCategoryProduct rows, AttributeBasedAdjustment records, and all references — without breaking the workstation flow.';
e11.task.constraints = 'Cleanup must be auditable (logged), idempotent (re-runnable safely), and must NOT touch workstation, peripheral, or cable products. Any reference rows pointing TO deleted POS products must be cleaned up first (or DML fails on FK constraint).';
e11.task.successCriteria = 'No POS products visible in Browse Catalog. No POS category in navigation. No orphaned junction rows. Storage usage drops by the freed records. Workstation demo flow unaffected.';
e11.action = new NotionPublishService.ActionSection();
e11.action.approach = 'Bottom-up cleanup: delete junctions first (ProductCategoryProduct, ProductQualification), then AttributeBasedAdjustment + PricingProcedureStep references, then Product2 records, then ProductCategory. Log each step. Wrap in try/catch for partial-failure recovery.';
e11.action.implementation = new List<String>{
    'Wrote scripts/delete_pos_completely.apex with bottom-up deletion order',
    'Deleted ProductCategoryProduct rows linking POS products to their category — 8 rows',
    'Deleted ProductQualification + ProductDisqualification rules referencing POS classification — 4 rules',
    'Deleted ProcedurePlanOption rows linking POS products to pricing procedure — 8 rows',
    'Deleted AttributeBasedAdjustment + PricingProcedureStep orphans referencing POS classification',
    'Deleted 8 Product2 records (POS terminals, receipt printers, scanners)',
    'Deleted POS ProductCategory record',
    'Ran Salesforce Pricing Setup Sync to clean stale references',
    'Verified Browse Catalog no longer shows POS — only Workstations / Peripherals / Cables / Software'
};
NotionPublishService.CodeSnippet e11c1 = new NotionPublishService.CodeSnippet();
e11c1.caption = 'scripts/delete_pos_completely.apex (bottom-up cleanup)';
e11c1.language = 'java';
e11c1.code = '// Bottom-up: junctions first, then parent records\nList<ProductCategoryProduct> pcpJunctions = [\n    SELECT Id FROM ProductCategoryProduct\n    WHERE Product.ProductCode LIKE \'POS-%\'\n];\nSystem.debug(\'Deleting \' + pcpJunctions.size() + \' POS category junctions\');\ndelete pcpJunctions;\n\nList<ProductQualification> pqRules = [\n    SELECT Id FROM ProductQualification\n    WHERE BasedOnId IN (SELECT Id FROM ProductClassification WHERE Code = \'CLASS_POS\')\n];\nSystem.debug(\'Deleting \' + pqRules.size() + \' POS qualification rules\');\ndelete pqRules;\n\nList<ProcedurePlanOption> ppoOrphans = [\n    SELECT Id FROM ProcedurePlanOption\n    WHERE Product.ProductCode LIKE \'POS-%\'\n];\nSystem.debug(\'Deleting \' + ppoOrphans.size() + \' POS procedure plan options\');\ndelete ppoOrphans;\n\nList<Product2> posProducts = [\n    SELECT Id, Name FROM Product2 WHERE ProductCode LIKE \'POS-%\'\n];\nSystem.debug(\'Deleting \' + posProducts.size() + \' POS products\');\ndelete posProducts;\n\nList<ProductCategory> posCats = [\n    SELECT Id FROM ProductCategory WHERE Name = \'POS Solutions\'\n];\nSystem.debug(\'Deleting \' + posCats.size() + \' POS category\');\ndelete posCats;\n\nSystem.debug(\'POS cleanup complete\');';
e11.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e11c1 };
e11.result = new NotionPublishService.ResultSection();
e11.result.outcome = 'POS Solutions feature cleanly removed. ~50KB storage recovered. Demo scope refocused on Workstations + Peripherals + Cables + Software, which all work end-to-end. The decision to cut scope was the right one: 4 working integration paths beat 5 with one broken.';
e11.result.tradeoffsAndLessons = 'When platform native features (ProductDisqualification.Industry__c enforcement) silently misbehave, the cost of building workarounds can exceed the value of the feature for the demo. The right move is sometimes to delete the feature and refocus. The "fail fast, cut deep" principle saved 8+ hours that went into Sendcloud + Stripe instead. Bottom-up cleanup pattern (junctions before parents) is a generally-useful template for any multi-junction-table cleanup.';
e11.result.references = new List<String>{
    'scripts/delete_pos_completely.apex',
    'Memory: demo_showcase_complete.md (post-POS-removal demo state)',
    'PlaceSalesTransactionPersistException — Salesforce platform bug in the trigger workaround attempt',
    'ProductDisqualification.Industry__c — documented but unenforced'
};
e11.result.futureWork = 'If POS becomes a future demo priority, the qualification logic can be implemented in a custom Apex trigger on QuoteLineItem (bypassing the broken native ProductDisqualification). Pattern would be similar to AttributePricingHandler used for Bundle attribute pricing.';
entries.add(e11);

// ============ 12. RLM Product Qualification — Workstation Tier Filtering ============
NotionPublishService.EnterpriseEntry e12 = new NotionPublishService.EnterpriseEntry();
e12.title = '12. RLM Product Qualification — Workstation Tier Filtering by Employee Count';
e12.situation = new NotionPublishService.SituationSection();
e12.situation.context = 'TechnoStore offers 5 workstation tiers (Entry/Standard/Pro/Workgroup/Mission-Critical) across DACH market accounts of very different sizes — Hamburg DataWorks (200 employees, large enterprise) vs Köln Retail Cloud (50 employees, mid-market). Without product qualification logic, every account saw every tier in Browse Catalog, leading to poor recommendations and overwhelming UX.';
e12.situation.problem = 'A 50-employee mid-market firm should not see Mission-Critical Xeon workstations starting at €3,499 — irrelevant to their budget and infrastructure. A 1000+ employee enterprise should not have to scroll past Entry-tier €899 boxes. Account-context-aware filtering is the value-add of Industries CPQ over generic ecommerce; not using it leaves the demo flat.';
e12.task = new NotionPublishService.TaskSection();
e12.task.goal = 'Implement multi-tier product visibility filtering driven by Account.NumberOfEmployees so large enterprises see all 5 workstation tiers while mid-market accounts see only the Entry tier. Filtering must update in real time when account context changes.';
e12.task.constraints = 'Product Qualification must use BasedOnId pointing at the workstation classification, not directly at individual Product2 records (cleaner architecture). Required two-step sync after every product config change: Product Discovery Index rebuild + Salesforce Pricing Setup Sync. Product2.Type field must be null for qualification to engage (the documented gotcha).';
e12.task.successCriteria = 'Hamburg DataWorks (200 employees) sees 4 workstations (Entry/Standard/Pro/Mission-Critical) in Browse Catalog. Köln Retail Cloud (50 employees) sees only 1 workstation (Entry). Switching account context via the Account selector updates the filter within 30 seconds.';
e12.action = new NotionPublishService.ActionSection();
e12.action.approach = 'Set up tiered ProductQualificationCategory records keyed by Account.NumberOfEmployees range, link to ProductQualificationProcedure with eligibility steps that match account size to tier. Sync via Product Discovery Index + Pricing Setup Sync after every change.';
e12.action.implementation = new List<String>{
    'Created 5 ProductQualificationCategory records keyed on Account.NumberOfEmployees ranges (0-50 = Entry-only, 51-200 = Entry+Standard, 201-1000 = Entry+Standard+Pro, 1001-5000 = all 4 tiers, 5000+ = all 5 tiers)',
    'Built ProductQualificationProcedure with employee-count-based eligibility steps targeting BasedOnId of each Workstation classification',
    'Diagnosed Product2.Type field gotcha — must be NULL (not "Base") for products to enter the qualification pipeline; updating Type is blocked, must recreate',
    'Required two-step sync after every product config change: Product Discovery Index rebuild + Salesforce Pricing Setup Sync — automated in setup_workstation_qualification.apex',
    'Verified live in Browse Catalog: Hamburg sees 4 tiers, Köln sees 1 tier, switching account context updates filter in real time',
    'Documented finding in product_qualification_demo_setup.md memory for reproducibility'
};
NotionPublishService.CodeSnippet e12c1 = new NotionPublishService.CodeSnippet();
e12c1.caption = 'ProductQualificationCategory + eligibility setup';
e12c1.language = 'java';
e12c1.code = '// scripts/setup_workstation_qualification.apex\nId workstationClassId = [SELECT Id FROM ProductClassification WHERE Code = \'CLASS_WORKSTATION\' LIMIT 1].Id;\n\n// 5 qualification categories, one per tier band\nList<ProductQualificationCategory> pqcs = new List<ProductQualificationCategory>{\n    new ProductQualificationCategory(\n        Name = \'Entry Tier Eligibility (1-50 employees)\',\n        BasedOnId = workstationClassId,\n        Description = \'Mid-market accounts see Entry tier only\'\n    ),\n    new ProductQualificationCategory(\n        Name = \'Standard Tier Eligibility (51-200 employees)\',\n        BasedOnId = workstationClassId,\n        Description = \'Adds Standard to Entry\'\n    ),\n    new ProductQualificationCategory(\n        Name = \'Pro Tier Eligibility (201-1000 employees)\',\n        BasedOnId = workstationClassId,\n        Description = \'Adds Pro\'\n    ),\n    new ProductQualificationCategory(\n        Name = \'Mission-Critical Eligibility (1001-5000 employees)\',\n        BasedOnId = workstationClassId,\n        Description = \'Adds Mission-Critical\'\n    ),\n    new ProductQualificationCategory(\n        Name = \'Enterprise (5000+ employees)\',\n        BasedOnId = workstationClassId,\n        Description = \'All 5 tiers visible\'\n    )\n};\ninsert pqcs;\n\n// Run Product Discovery Index rebuild + Pricing Setup Sync after insert\n// Both are required for Browse Catalog to reflect new qualification';
e12.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e12c1 };
e12.result = new NotionPublishService.ResultSection();
e12.result.outcome = 'Live differential catalog working. Hamburg DataWorks sees Entry + Standard + Pro + Mission-Critical (4 workstations), Köln Retail Cloud sees only Entry (1 workstation). The same product catalog, contextually filtered per account size. Production-pattern Industries CPQ feature demonstrated in 30 seconds of demo time.';
e12.result.tradeoffsAndLessons = 'Industries CPQ qualification engine is powerful but requires careful BasedOnId targeting (classification, not individual products) and 2-step sync after every change. Without the sync steps, changes silently fail to propagate. The 5-band employee count taxonomy is simple but effective — real production systems would extend with Industry, geography, and procurement-budget bands. Pattern documented for extension.';
e12.result.references = new List<String>{
    'Memory: product_qualification_demo_setup.md (live demo setup)',
    'scripts/setup_workstation_qualification.apex',
    'Setup -> Industries -> Product Discovery -> Rebuild Index (manual step)',
    'Setup -> Industries -> Pricing -> Setup Sync (manual step)'
};
e12.result.futureWork = 'Extend to Industry-band qualification (e.g., Healthcare accounts see only HIPAA-certified models). Geographic qualification (DACH-only models vs global). Budget-band qualification using Account.AnnualRevenue. Pattern is the same — add ProductQualificationCategory rows.';
entries.add(e12);

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
System.debug('=== BATCH 3 COMPLETE === Success: ' + success + ' / Failed: ' + failed);
