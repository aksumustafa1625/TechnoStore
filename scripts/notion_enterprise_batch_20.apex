// Enterprise STAR entry 51: Notion format refactor (meta entry — the refactor itself)

List<NotionPublishService.EnterpriseEntry> entries = new List<NotionPublishService.EnterpriseEntry>();

// ============ 51. Notion Format Refactor — From 6-Call Orchestration to Single POST ============
NotionPublishService.EnterpriseEntry e51 = new NotionPublishService.EnterpriseEntry();
e51.title = '51. Notion Format Refactor — From 6-Call Orchestration to Single POST + Flat Headings';

// SITUATION
e51.situation = new NotionPublishService.SituationSection();
e51.situation.context = 'TechnoStore portfolio publishes 50 STAR-format entries to Notion via Apex (NotionPublishService.publishEnterprise). The original design used 3-level toggle nesting — Page → Main toggle (Situation/Task/Action/Result) → Sub-toggle (Context/Problem/Goal/Constraints/etc.) → Content paragraphs. Notion API has a hard 2-level nesting limit per request, so this 3-level structure required a 6-API-call orchestration per entry: 1 POST for the page + 1 PATCH for main toggles + 4 PATCH calls to fill each main toggle with its sub-toggles. Documented as ADR-010 with rate-limit pacing strategy spread across 19 batch scripts.';
e51.situation.problem = 'Two real costs emerged in production. First, performance: 50 entries × 6 calls = 300 API calls total per full republish, with ~25 minutes elapsed time at Notion 3 RPS pacing. Second, and more importantly, UX: portfolio readers had to click through 3 layers of toggles to reach the actual content. Sub-section names (Context, Problem, Goal, Constraints, Success Criteria, Approach, Implementation, Code, Outcome, Lessons Learned, References, Future Work) were all collapsed by default. Each entry required ~13 clicks to fully expand. User feedback was direct: the structure was exhausting to read. Originally optimized for the wrong constraint — Notion API limits — instead of the UX constraint.';

// TASK
e51.task = new NotionPublishService.TaskSection();
e51.task.goal = 'Restructure the publishing logic so the 4 main S/T/A/R toggles remain collapsible (recruiter wants section-level overview) but inner sub-sections render as flat heading_3 + content blocks directly — eliminating nested toggles and reducing required clicks from ~13 per entry to 4.';
e51.task.constraints = 'Notion API still allows only 2 levels of nesting per POST/PATCH request (Page → toggle → toggle.children of leaf blocks). The new structure must fit within this limit. Backward compatibility with the legacy smoke test (NotionPublishService.publish using flat StarEntry) must be preserved — its tests are referenced in older scripts. Cannot delete the already-published 50 entries via this code path because that requires Notion API delete permissions and bulk operations not in scope; manual cleanup via Notion UI is the cleanup path.';
e51.task.successCriteria = 'Single POST per entry (no multi-step orchestration). New entries render with flat heading_3 sub-sections — Context / Problem / Goal etc. appear as bold headings, not toggles. Content visible immediately when a main toggle is expanded. All 50 entries re-publish without failure. Total batch time under 10 minutes elapsed. Code metrics: NotionPublishService.cls overall length reduced (orchestration code removed).';

// ACTION
e51.action = new NotionPublishService.ActionSection();
e51.action.approach = 'Recognize that the Notion 2-level nesting limit was never the root problem — the 3-level toggle design was an over-engineered response to it. Flat heading_3 + paragraph blocks inside the main toggle fit cleanly within the 2-level limit AND solve the UX issue at the same time. Refactor: replace inner buildToggle calls with a new appendSection helper that emits heading_3 + content blocks sequentially. Simplify publishEnterprise from the 6-call orchestration to a single POST with the full children tree built in memory before send.';
e51.action.implementation = new List<String>{
    'Added heading3() block builder helper alongside the existing heading2() — emits a Notion heading_3 block with rich_text content',
    'Added appendSection(List<Object> target, String title, List<Object> content) — appends a heading_3 block then the content blocks, with a "(no content)" paragraph fallback when content is empty',
    'Refactored 4 build*Children methods (buildSituationChildren, buildTaskChildren, buildActionChildren, buildResultChildren) to call appendSection instead of buildToggle for sub-sections',
    'Simplified publishEnterprise() from multi-step orchestration (page create + 4 toggle appends + fills) to a single POST /v1/pages call with the full children tree as the request body',
    'Removed the fillToggle() helper — no longer needed because there are no second-pass PATCH calls',
    'Updated the class header comment with the new architecture diagram, the refactor date (2026-05-14), and the rationale (UX over API limits)',
    'Created scripts/test_notion_enterprise_format.apex — single-entry smoke test that verified the new structure renders correctly before bulk republish',
    'Deployed the updated class via sf project deploy start to the TechnoStore Dev Edition org',
    'Ran the 19 existing batch scripts sequentially (notion_enterprise_batch_1.apex through _19.apex) — all 50 entries re-published with 0 failures in ~5 minutes total elapsed'
};
NotionPublishService.CodeSnippet snippet1 = new NotionPublishService.CodeSnippet();
snippet1.caption = 'Before — 3-level toggle nesting (buildSituationChildren old)';
snippet1.language = 'java';
snippet1.code = 'private static List<Object> buildSituationChildren(SituationSection s) {\n    List<Object> subs = new List<Object>();\n    if (s != null) {\n        subs.add(buildToggle(\'Context\', paragraphsFrom(s.context)));\n        subs.add(buildToggle(\'Problem\', paragraphsFrom(s.problem)));\n    }\n    return subs;\n}';
NotionPublishService.CodeSnippet snippet2 = new NotionPublishService.CodeSnippet();
snippet2.caption = 'After — flat heading_3 + content (using appendSection helper)';
snippet2.language = 'java';
snippet2.code = 'private static List<Object> buildSituationChildren(SituationSection s) {\n    List<Object> out = new List<Object>();\n    if (s == null) return out;\n    appendSection(out, \'Context\', paragraphsFrom(s.context));\n    appendSection(out, \'Problem\', paragraphsFrom(s.problem));\n    return out;\n}\n\nprivate static void appendSection(List<Object> target, String title, List<Object> content) {\n    target.add(heading3(title));\n    if (content == null || content.isEmpty()) {\n        target.add(paragraph(\'(no content)\'));\n        return;\n    }\n    target.addAll(content);\n}';
NotionPublishService.CodeSnippet snippet3 = new NotionPublishService.CodeSnippet();
snippet3.caption = 'Before — publishEnterprise multi-step (6 calls)';
snippet3.language = 'java';
snippet3.code = '// 1. Create page with title only\nString pageId = postPage(entry.title);\n\n// 2. Append 4 empty main toggles, capture their ids\nString[] toggleIds = appendMainToggles(pageId);\n\n// 3-6. Fill each main toggle with its sub-toggle tree\nfillToggle(toggleIds[0], buildSituationChildren(entry.situation));\nfillToggle(toggleIds[1], buildTaskChildren(entry.task));\nfillToggle(toggleIds[2], buildActionChildren(entry.action));\nfillToggle(toggleIds[3], buildResultChildren(entry.result));\n\nreturn pageId;';
NotionPublishService.CodeSnippet snippet4 = new NotionPublishService.CodeSnippet();
snippet4.caption = 'After — publishEnterprise single POST (1 call)';
snippet4.language = 'java';
snippet4.code = 'List<Object> children = new List<Object>{\n    buildToggle(\'Situation\', buildSituationChildren(entry.situation)),\n    buildToggle(\'Task\',      buildTaskChildren(entry.task)),\n    buildToggle(\'Action\',    buildActionChildren(entry.action)),\n    buildToggle(\'Result\',    buildResultChildren(entry.result))\n};\n\nMap<String, Object> body = new Map<String, Object>{\n    \'parent\' => new Map<String, String>{ \'page_id\' => cfg.Parent_Page_Id__c },\n    \'properties\' => titleProperties(entry.title),\n    \'children\' => children\n};\nHttpResponse resp = sendNotion(\'POST\', \'https://api.notion.com/v1/pages\', body, cfg.Token__c);\nreturn parsePageId(resp);';
e51.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snippet1, snippet2, snippet3, snippet4 };

// RESULT
e51.result = new NotionPublishService.ResultSection();
e51.result.outcome = 'All 50 enterprise entries re-published in approximately 5 minutes total elapsed time (vs ~25 minutes previously). Zero failures across all 19 batch scripts. New structure renders correctly: 4 collapsible main toggles per page, flat heading_3 sub-sections inside (Context, Problem, Goal, Constraints, Success Criteria, etc.), content immediately visible when the main toggle is expanded. API call count reduced from 300 to 50 (6× reduction). The 1 smoke test entry plus this meta entry (#51) total 52 new pages. Old 50 entries remain in Notion pending manual cleanup via the Notion UI.';
e51.result.tradeoffsAndLessons = 'The previous 6-call orchestration was technically correct — it worked within Notion stated 2-level nesting limits — but it optimized for the wrong constraint. The real binding constraint was UX, not API rate limits. The lesson: when designing a workaround for a platform limit, periodically question whether the limit you are optimizing for is actually the binding one. Sometimes the workaround creates a worse problem than the original limit would have caused if you had accepted it. Two specific lessons emerged. First, ADR-010 transitioned from Status: Accepted to Status: Superseded with the new ADR (or revised ADR-010 itself) documenting why we changed direction. This is healthy — architectural artifacts should age gracefully, not become stale or hidden. Second, the new structure is also less code to maintain: the orchestration helper fillToggle and the multi-step state tracking in publishEnterprise are gone, replaced by a single declarative build-tree-then-POST flow.';
e51.result.references = new List<String>{
    'force-app-services/main/default/classes/NotionPublishService.cls — refactored 2026-05-14',
    'scripts/test_notion_enterprise_format.apex — single-entry smoke test for the new format',
    'scripts/notion_enterprise_batch_1.apex through _19.apex — 50 entries re-publish scripts (unchanged data, new output structure)',
    'ADR-010 — Notion 6-Call Orchestration (Status: Superseded by single-POST refactor)',
    'Notion API documentation: https://developers.notion.com/reference/block — children nesting limits',
    'User UX feedback driving the refactor: the original 3-level click pattern was tiring to read'
};
e51.result.futureWork = 'Document this refactor in the Solution Blueprint Risks and Technical Debt section as a worked example of API-workaround-that-became-technical-debt. Consider establishing a quarterly review of long-lived workarounds: are they still needed? Are they still the right approach? When platform limits change or our requirements shift, the original workaround may no longer be the optimal solution. The pattern of taking a workaround, documenting it as an ADR, then later superseding the ADR when conditions change is a healthy architectural practice that this refactor exemplifies.';
entries.add(e51);

// =================== Publish loop ===================
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
System.debug('=== BATCH 20 COMPLETE (entry 51 — meta refactor) === Success: ' + success + ' / Failed: ' + failed);
