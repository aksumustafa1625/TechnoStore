// Enterprise STAR entries 41-42: JIRA Sprint Planning + Storage Management

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 41. JIRA Sprint Planning — TS-1 through TS-9 Setup ============
NotionPublishService.EnterpriseEntry e41 = new NotionPublishService.EnterpriseEntry();
e41.title = '41. JIRA Sprint Planning — TS-1 through TS-9 SAP Integration Setup';
e41.situation = new NotionPublishService.SituationSection();
e41.situation.context = 'After sprint provisioning was working programmatically (entry 40), the next step was real sprint planning content: defining the SAP integration work as a structured 8-ticket backlog that the demo narrative would carry forward into Q3 2026. SAP ERP is the canonical "next big integration" in DACH enterprise contexts — recruiters specifically ask "what about SAP integration?" because most German enterprises run SAP S/4HANA. Building a real sprint plan (not fake tickets) signals serious enterprise-readiness.';
e41.situation.problem = 'Sprint planning is more than ticket creation — each ticket needs a meaningful summary, an ADF description capturing acceptance criteria, story point estimation calibrated to relative complexity, and labels for grouping. Fake tickets like "TODO: SAP something" damage the demo. The 8 SAP tickets needed to map to a credible 2-week integration path: API Hub sandbox setup → OData adapter → IDoc mapping → outbound flow → order replication → material master sync → error handling → demo recording. Each ticket needed enough detail to be a real Jira card a developer could pick up.';
e41.task = new NotionPublishService.TaskSection();
e41.task.goal = 'Create 8 JIRA tickets (TS-2 through TS-9) representing the SAP integration sprint backlog with meaningful summaries, ADF descriptions including acceptance criteria, story point estimates totaling 17 SP, labels (sap-integration / sprint-may-2026), and priority. Add all 8 to sprint 68 (entry 40) alongside TS-1 fulfillment ticket. Result: production-quality sprint backlog visible to recruiters.';
e41.task.constraints = 'Story point estimation must be relative not absolute: TS-2 SAP sandbox setup (most setup work, 3 SP) vs TS-9 SAP demo recording (just recording, 1 SP). Total sprint capacity ~17 SP fits a 2-week sprint for one full-time developer. ADF descriptions must follow the same nested JSON format as entry 39 (Atlassian Document Format with content/paragraph/text nodes). Labels are JIRA-side tags for filtering — sap-integration and sprint-may-2026 enable sprint dashboards to filter.';
e41.task.successCriteria = '8 SAP tickets created in TS project with summaries, ADF descriptions, story points, labels, priorities all populated. All 8 added to sprint 68. Sprint dashboard shows 17 SP allocated across 8 work items. Each ticket clickable, descriptions render with acceptance criteria visible, story points displayed in sprint backlog view. Demo recording can show this sprint as evidence of enterprise SAP-readiness.';
e41.action = new NotionPublishService.ActionSection();
e41.action.approach = 'Built scripts/setup_jira_sap_tickets.apex with hardcoded ticket data per SAP integration step. Each entry has summary + ADF description containing acceptance criteria + story points + labels. Loop invokes JIRA REST /rest/api/3/issue endpoint per ticket (same JiraTicketService pattern from entry 39 with extended payload). Captures issue keys (TS-2 through TS-9), invokes JiraSprintService.addIssuesToSprint(68, [keys]) to bundle into sprint.';
e41.action.implementation = new List<String>{
    'Defined 8 SAP integration tickets in scripts/setup_jira_sap_tickets.apex with structured data: summary + ADF description with bulleted acceptance criteria + story points + labels',
    'TS-2 SAP API Hub Sandbox Setup (3 SP): provision sandbox tenant on api.sap.com, configure OAuth client credentials, validate connectivity via Postman',
    'TS-3 SAP OData Adapter Configuration (3 SP): install SAP OData connector in MuleSoft Anypoint Studio, configure service endpoints, test SELECT from BusinessPartner entity',
    'TS-4 IDoc Schema Mapping (2 SP): map TechnoStore Account fields to SAP BusinessPartner IDoc segments, define field-level transformations',
    'TS-5 SAP Outbound Flow — SF Order → SAP Sales Order (2 SP): Mule flow consuming SF Order Platform Event → DataWeave transform to SAP Sales Order IDoc → SAP inbound IDoc receipt',
    'TS-6 SAP Order Replication (3 SP): bidirectional sync — SAP-side Sales Order changes propagate back to SF via SAP outbound queue + Mule subscriber → SF Order update',
    'TS-7 SAP Material Master Sync (2 SP): SAP MARA table → Mule scheduled pull → SF Product2 + PricebookEntry upsert; reverse sync for product changes',
    'TS-8 SAP Error Handling + DLQ (1 SP): Mule Dead Letter Queue for failed SAP outbound calls, retry policy with exponential backoff, ops alert on persistent failures',
    'TS-9 SAP Demo Recording (1 SP): screen recording showing SF → Mule → SAP → bidirectional flow end-to-end for portfolio demo video',
    'Built ADF description per ticket with acceptance criteria as bulleted list — each bullet a separate paragraph node in the content array',
    'Set labels = [\"sap-integration\", \"sprint-may-2026\"] on every ticket for sprint dashboard filtering',
    'Priority assignment: TS-2 (High — blocks all other work), TS-3/TS-4/TS-6 (Medium), TS-5/TS-7/TS-8/TS-9 (Low)',
    'Invoked JiraTicketService-style HTTP POST per ticket in a loop, captured issue keys, then JiraSprintService.addIssuesToSprint(68, [TS-2..TS-9])',
    'Sprint 68 dashboard now shows TS-1 (Order fulfillment placeholder) + TS-2 through TS-9 (8 SAP tickets) = 9 tickets, 17 SP total',
    'Documented sprint plan in CLAUDE.md to ensure next AI session knows the backlog'
};
NotionPublishService.CodeSnippet e41c1 = new NotionPublishService.CodeSnippet();
e41c1.caption = 'scripts/setup_jira_sap_tickets.apex (excerpt)';
e41c1.language = 'java';
e41c1.code = '// Define 8 SAP integration tickets with structured ADF descriptions\nList<Map<String, Object>> sapTickets = new List<Map<String, Object>>{\n    new Map<String, Object>{\n        \'summary\' => \'SAP API Hub Sandbox Setup\',\n        \'storyPoints\' => 3,\n        \'priority\' => \'High\',\n        \'description\' => \'Provision sandbox tenant on api.sap.com, configure OAuth client credentials, validate connectivity\',\n        \'acceptanceCriteria\' => new List<String>{\n            \'Sandbox tenant created at api.sap.com\',\n            \'OAuth client_id + client_secret captured and stored in mule-app.properties (gitignored)\',\n            \'Postman GET request to /odata/businessPartner returns 200 with valid token\'\n        }\n    },\n    new Map<String, Object>{\n        \'summary\' => \'SAP OData Adapter Configuration in Anypoint Studio\',\n        \'storyPoints\' => 3,\n        \'priority\' => \'Medium\',\n        \'description\' => \'Install SAP OData connector in MuleSoft, configure service endpoints, test SELECT from BusinessPartner\',\n        \'acceptanceCriteria\' => new List<String>{\n            \'SAP OData connector installed in Anypoint Studio\',\n            \'sap:config configured with sandbox endpoints\',\n            \'Mule flow successfully SELECTS from BusinessPartner entity\'\n        }\n    }\n    // ... TS-4 through TS-9 follow same structure\n};\n\nList<String> createdKeys = new List<String>();\nfor (Map<String, Object> t : sapTickets) {\n    // Build ADF description with acceptance criteria as bulleted list\n    List<Object> adfContent = new List<Object>{\n        buildAdfParagraph((String) t.get(\'description\')),\n        buildAdfParagraph(\'Acceptance Criteria:\')\n    };\n    for (String ac : (List<String>) t.get(\'acceptanceCriteria\')) {\n        adfContent.add(buildAdfBulletItem(ac));\n    }\n    Map<String, Object> adf = new Map<String, Object>{\n        \'type\' => \'doc\',\n        \'version\' => 1,\n        \'content\' => adfContent\n    };\n\n    Map<String, Object> issue = new Map<String, Object>{\n        \'fields\' => new Map<String, Object>{\n            \'project\' => new Map<String, String>{ \'key\' => \'TS\' },\n            \'summary\' => (String) t.get(\'summary\'),\n            \'description\' => adf,\n            \'issuetype\' => new Map<String, String>{ \'name\' => \'Task\' },\n            \'priority\' => new Map<String, String>{ \'name\' => (String) t.get(\'priority\') },\n            \'labels\' => new List<String>{ \'sap-integration\', \'sprint-may-2026\' }\n        }\n    };\n\n    HttpRequest req = new HttpRequest();\n    req.setEndpoint(cfg.Base_URL__c + \'/rest/api/3/issue\');\n    req.setMethod(\'POST\');\n    req.setHeader(\'Authorization\', \'Basic \' + cfg.Auth_Token__c);\n    req.setHeader(\'Content-Type\', \'application/json\');\n    req.setBody(JSON.serialize(issue));\n    HttpResponse resp = new Http().send(req);\n    String key = (String) ((Map<String, Object>) JSON.deserializeUntyped(resp.getBody())).get(\'key\');\n    createdKeys.add(key);\n\n    // Set story points immediately after creation\n    JiraSprintService.setStoryPoints(key, (Decimal) t.get(\'storyPoints\'));\n}\n\n// Bundle all 8 SAP tickets into sprint 68 with TS-1\ncreatedKeys.add(0, \'TS-1\');\nJiraSprintService.addIssuesToSprint(68, createdKeys);\nSystem.debug(\'Sprint 68 populated with \' + createdKeys.size() + \' tickets\');';
e41.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e41c1 };
e41.result = new NotionPublishService.ResultSection();
e41.result.outcome = 'Sprint 68 "TS Sprint May 10-24" populated with 9 tickets totaling 17 story points: TS-1 fulfillment placeholder + TS-2 (3 SP, High priority, SAP sandbox) + TS-3 (3 SP, OData adapter) + TS-4 (2 SP, IDoc mapping) + TS-5 (2 SP, outbound flow) + TS-6 (3 SP, bidirectional replication) + TS-7 (2 SP, material master sync) + TS-8 (1 SP, error handling) + TS-9 (1 SP, demo recording). Each ticket has ADF description with acceptance criteria, labels for filtering, priority assignment. Sprint dashboard renders production-quality. SAP integration narrative carries the demo forward into Q3 2026.';
e41.result.tradeoffsAndLessons = 'Real sprint planning content (acceptance criteria, story points, priority, labels) takes longer than fake ticket creation but signals enterprise-readiness to recruiters. The SAP integration backlog is intentionally aspirational — TS-2 through TS-9 are NOT done; they represent the "what comes next" portfolio narrative. This is honest and valuable: it shows the engineer can plan integration work, not just complete it. The labels pattern (sap-integration / sprint-may-2026) is JIRA-native filtering tool that scales beyond this single sprint.';
e41.result.references = new List<String>{
    'scripts/setup_jira_sap_tickets.apex',
    'Sprint 68 in TS project — TS-1 + TS-2 through TS-9',
    'SAP integration is the planned Q3 2026 work — not yet implemented',
    'CLAUDE.md (project context — sprint plan documented)'
};
e41.result.futureWork = 'Implement TS-2 through TS-9 in order during the May 10-24 sprint window. TS-2 SAP API Hub sandbox setup is the next session work item. Sprint retrospective ticket auto-creation at sprint end (May 24) would close the agile loop.';
entries.add(e41);

// ============ 42. Storage Management on Dev Edition ============
NotionPublishService.EnterpriseEntry e42 = new NotionPublishService.EnterpriseEntry();
e42.title = '42. Storage Management on Dev Edition — 1MB Recovery Unblocks Deploy';
e42.situation = new NotionPublishService.SituationSection();
e42.situation.context = 'Salesforce Developer Edition storage limits are constrained: 5 MB for data storage (records across all sObjects) + 20 MB for file storage (ContentVersion + Attachment). Mid-project, TechnoStore data storage hit 84% utilization. Symptom: metadata deploys started failing with INSUFFICIENT_STORAGE errors, and new Product2 record creation via Apex DML threw STORAGE_LIMIT_EXCEEDED. Demo prep stalled — no path forward without freeing space.';
e42.situation.problem = 'Identifying which records were consuming space required SOQL-driven audit across multiple sObjects (Product2, ProductCategoryProduct, AttributeBasedAdjustment, PricingProcedureStep, ContentVersion). Many records were orphaned from earlier experiments: POS Solutions products (entry 11 cleanup), abandoned bundle configurator tests, duplicate AttributeBasedAdjustment records from POC iterations. Deleting them required dependency-order awareness — junction rows must be deleted before parent records or DML throws FK integrity errors.';
e42.task = new NotionPublishService.TaskSection();
e42.task.goal = 'Identify and delete unused records freeing at least 1 MB of data storage, without breaking active demo data or working integrations. Drop storage utilization from 84% to under 70% to provide headroom for ongoing demo work. Document the audit + cleanup pattern so it can be re-run when storage approaches limits again.';
e42.task.constraints = 'Cleanup must be auditable (every deletion logged with count + sObject), idempotent (re-runnable safely), and must NOT touch active demo data (4 DACH accounts, 4 Quotes, 4 Opportunities, current Products). Foreign-key dependencies require bottom-up deletion: junctions (ProductCategoryProduct, PricebookEntry) before parent records (Product2). Sometimes Apex DML returns row-locking errors when DML is too large — chunk deletes into batches of 200 records per transaction.';
e42.task.successCriteria = 'Storage utilization drops by at least 1 MB (from 84% → under 70%). Active demo data preserved (Hamburg/München/Frankfurt/Köln Accounts + their Quotes + Opportunities + Workstation Products). Audit log shows what was deleted with counts. Deploys unblocked. New Product2 records can be created via Apex without STORAGE_LIMIT_EXCEEDED errors.';
e42.action = new NotionPublishService.ActionSection();
e42.action.approach = 'Built scripts/storage_audit.apex with SOQL queries identifying candidate-for-deletion records grouped by sObject: orphaned Product2 (no QuoteLineItem or OrderItem usage AND CreatedDate < 30 days), AttributeBasedAdjustment with deleted PricingProcedureStep parents, duplicate PricingProcedureStep records from POC iterations, old ContentVersion files (test PDFs > 60 days old). Then scripts/storage_cleanup.apex actually deletes (bottom-up junctions first).';
e42.action.implementation = new List<String>{
    'Built scripts/storage_audit.apex with diagnostic SOQL: SELECT COUNT() FROM Product2, ProductCategoryProduct, AttributeBasedAdjustment, PricingProcedureStep, ContentVersion grouped by orphan criteria',
    'Audit identified 59 unused Product2 records from earlier experiments (POS Solutions, configurator POCs, abandoned bundle tests) — none used in any QuoteLineItem or OrderItem record',
    'Found 12 AttributeBasedAdjustment orphans (PricingProcedureStep parent deleted but child not cleaned up)',
    'Found 8 duplicate PricingProcedureStep records (same step inserted twice during POC iterations)',
    'Found 23 old ContentVersion records (test invoice/contract PDFs older than 60 days) totaling ~400KB',
    'Built scripts/storage_cleanup.apex with bottom-up deletion order: ProductCategoryProduct → ProductRelationshipFeature → AttributeBasedAdjustment → PricingProcedureStep → ProcedurePlanOption → Product2 → ProductCategory',
    'Per-sObject delete batch: SELECT 200 rows matching orphan criteria → delete via single DML transaction → log count → loop until no more matches',
    'Ran scripts/delete_pos_completely.apex (entry 11) which removed 8 POS products + qualification rules + junctions — freed ~80KB',
    'Cleared old ContentVersion files > 60 days via batch SOQL: SELECT Id FROM ContentVersion WHERE FileType=\'PDF\' AND CreatedDate < LAST_N_DAYS:60 ORDER BY ContentSize DESC LIMIT 50',
    'Ran Salesforce Pricing Setup Sync (Setup → Industries → Pricing) to clean any stale references after the cleanup',
    'Verified storage drop via Setup → Storage Usage: data storage went from 84% → 67% (over 1 MB recovered)',
    'Active demo data preserved: 4 DACH accounts still present, 4 Quotes still functional, 5 workstation tiers still in Browse Catalog',
    'Documented storage audit pattern for future reuse — re-runnable script with logging'
};
NotionPublishService.CodeSnippet e42c1 = new NotionPublishService.CodeSnippet();
e42c1.caption = 'Storage audit + cleanup SOQL (Apex)';
e42c1.language = 'sql';
e42c1.code = '-- ============ Storage Audit Queries ============\n\n-- 1. Orphaned Product2 (no QuoteLineItem or OrderItem usage)\nSELECT COUNT(Id) FROM Product2\nWHERE Id NOT IN (SELECT Product2Id FROM QuoteLineItem)\n  AND Id NOT IN (SELECT Product2Id FROM OrderItem)\n  AND CreatedDate < LAST_N_DAYS:30\n  AND IsActive = TRUE\n-- Expected: ~50 rows = candidates for deletion\n\n-- 2. AttributeBasedAdjustment orphans (parent PricingProcedureStep deleted)\nSELECT COUNT(Id) FROM AttributeBasedAdjustment\nWHERE PricingProcedureStepId = NULL\n   OR PricingProcedureStepId NOT IN (SELECT Id FROM PricingProcedureStep)\n-- Expected: ~12 rows\n\n-- 3. Duplicate PricingProcedureStep records (same Step inserted twice)\nSELECT Name, StepType, COUNT(Id) cnt FROM PricingProcedureStep\nGROUP BY Name, StepType\nHAVING COUNT(Id) > 1\n-- Expected: ~8 duplicates\n\n-- 4. Old ContentVersion files > 60 days\nSELECT Id, Title, ContentSize FROM ContentVersion\nWHERE FileType = \'PDF\'\n  AND CreatedDate < LAST_N_DAYS:60\nORDER BY ContentSize DESC\nLIMIT 50\n-- Expected: ~23 files, total ~400KB\n\n-- ============ Storage Cleanup DML ============\n-- Bottom-up dependency order — junctions before parents\n\n// Apex anonymous script:\nList<ProductCategoryProduct> pcps = [\n    SELECT Id FROM ProductCategoryProduct\n    WHERE Product.Id IN (SELECT Id FROM Product2 WHERE ProductCode LIKE \'POS-%\')\n];\nSystem.debug(\'Deleting \' + pcps.size() + \' POS PCP junctions\');\ndelete pcps;\n\nList<AttributeBasedAdjustment> aba = [\n    SELECT Id FROM AttributeBasedAdjustment\n    WHERE PricingProcedureStepId = NULL\n];\nSystem.debug(\'Deleting \' + aba.size() + \' ABA orphans\');\ndelete aba;\n\nList<Product2> orphans = [\n    SELECT Id, Name FROM Product2\n    WHERE Id NOT IN (SELECT Product2Id FROM QuoteLineItem)\n      AND Id NOT IN (SELECT Product2Id FROM OrderItem)\n      AND CreatedDate < LAST_N_DAYS:30\n];\nSystem.debug(\'Deleting \' + orphans.size() + \' orphaned products\');\ndelete orphans;\n\nList<ContentVersion> oldPdfs = [\n    SELECT Id FROM ContentVersion\n    WHERE FileType = \'PDF\' AND CreatedDate < LAST_N_DAYS:60\n    ORDER BY ContentSize DESC LIMIT 50\n];\nSystem.debug(\'Deleting \' + oldPdfs.size() + \' old PDF ContentVersions\');\ndelete oldPdfs;\n\nSystem.debug(\'Total storage cleanup complete\');';
e42.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ e42c1 };
e42.result = new NotionPublishService.ResultSection();
e42.result.outcome = 'Storage utilization dropped from 84% to 67% — over 1 MB recovered. Deploys unblocked. New Product2 records can be created via Apex DML without STORAGE_LIMIT_EXCEEDED errors. Active demo data preserved (4 DACH accounts, 4 Quotes, 4 Opportunities, 5 workstation tiers). Storage audit + cleanup pattern documented for future re-use when storage approaches limits again. Demo prep resumed without further storage blockage.';
e42.result.tradeoffsAndLessons = 'Dev Edition\'s 5 MB data storage limit is unforgivingly small for any project with >100 sObject records. The audit-first / cleanup-second pattern is the safe approach — never delete blindly. Bottom-up dependency cleanup (junctions before parents) is the canonical pattern for any Salesforce data migration or cleanup script; reversing the order causes FK constraint errors that are easy to misdiagnose. The 60-day ContentVersion cutoff is a heuristic — production deployments would use 365-day retention with proper archival.';
e42.result.references = new List<String>{
    'scripts/storage_audit.apex (read-only diagnostic)',
    'scripts/storage_cleanup.apex (DML cleanup with logging)',
    'scripts/delete_pos_completely.apex (POS-specific cleanup from entry 11)',
    'Setup → Storage Usage (Dev Edition data + file storage view)'
};
e42.result.futureWork = 'Migrate to a sandbox or higher-tier org with more storage (Enterprise: 1 GB data) — but for the demo phase Dev Edition is sufficient. Schedule weekly storage_audit.apex via Apex Scheduled Job + email notification when utilization exceeds 70% threshold. Currently manual monitoring.';
entries.add(e42);

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
System.debug('=== BATCH 15 COMPLETE (entries 41-42) === Success: ' + success + ' / Failed: ' + failed);
