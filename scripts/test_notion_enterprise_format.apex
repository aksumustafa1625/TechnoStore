// Smoke test: verify the new flat-heading format works end-to-end.
// Publishes ONE EnterpriseEntry with all S/T/A/R sections + sub-section headings.
// After running, verify in Notion:
//   - Page title appears
//   - 4 main toggles (Situation, Task, Action, Result) are collapsible
//   - Inside each toggle: heading_3 sub-sections + content directly underneath (NO inner toggles)

NotionPublishService.EnterpriseEntry e = new NotionPublishService.EnterpriseEntry();
e.title = '🧪 Format Smoke Test — Flat Headings v2 (2026-05-14)';

// SITUATION
e.situation = new NotionPublishService.SituationSection();
e.situation.context = 'Refactored NotionPublishService to emit flat heading_3 sub-sections inside the main S/T/A/R toggles, replacing the previous 3-level toggle nesting. This smoke test verifies the new structure publishes correctly in a single POST call.';
e.situation.problem = 'Previous structure (3-level toggles) required 6 API calls per entry AND created UX fatigue — readers had to click through 3 layers of toggles to reach content. The flat structure (heading_3 + paragraph inside main toggle) is 1 API call AND cleaner UX.';

// TASK
e.task = new NotionPublishService.TaskSection();
e.task.goal = 'Publish one test entry using publishEnterprise() and confirm the new structure renders correctly in Notion.';
e.task.constraints = 'Notion API 2-level nesting limit per request — page → toggle → content. Cannot have toggle inside toggle inside the same POST.';
e.task.successCriteria = 'Page appears under parent. Main toggles collapsible. Sub-section headings flat (no toggle arrows). Content visible immediately when main toggle is expanded.';

// ACTION
e.action = new NotionPublishService.ActionSection();
e.action.approach = 'Refactored buildSituationChildren / buildTaskChildren / buildActionChildren / buildResultChildren to emit heading_3 + content sequentially via the appendSection helper, instead of nested toggle blocks.';
e.action.implementation = new List<String>{
    'Added heading3() block builder helper alongside existing heading2()',
    'Added appendSection(target, title, content) helper to emit heading_3 + content blocks',
    'Refactored 4 buildXChildren methods to use appendSection instead of buildToggle for sub-sections',
    'Simplified publishEnterprise() from 6-call orchestration to single POST with full children tree',
    'Removed fillToggle() helper (no longer needed)'
};
NotionPublishService.CodeSnippet snippet = new NotionPublishService.CodeSnippet();
snippet.caption = 'Sample appendSection helper';
snippet.language = 'java';  // Notion accepts 'java'; Apex syntax is Java-derived
snippet.code = 'private static void appendSection(List<Object> target, String title, List<Object> content) {\n    target.add(heading3(title));\n    if (content == null || content.isEmpty()) {\n        target.add(paragraph(\'(no content)\'));\n        return;\n    }\n    target.addAll(content);\n}';
e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snippet };

// RESULT
e.result = new NotionPublishService.ResultSection();
e.result.outcome = 'If you see this entry rendered with: (1) page title at top, (2) 4 collapsible main toggles, (3) flat headings inside (Context, Problem, Goal, Constraints, etc.), (4) content immediately visible — the refactor works.';
e.result.tradeoffsAndLessons = 'Sometimes API limits are not the binding constraint — UX is. The previous 6-call orchestration respected Notion API limits but created click fatigue. Flat headings respect both limits AND UX. The lesson: question whether the constraint you are working around is the real constraint.';
e.result.references = new List<String>{
    'NotionPublishService.cls — refactored 2026-05-14',
    'Notion API: https://developers.notion.com/reference/block',
    'ADR-010 — Notion 6-call orchestration (now Superseded by single-POST refactor)'
};
e.result.futureWork = 'After this smoke test verifies the new format, re-publish all 50 enterprise entries via the existing 19 batch scripts.';

try {
    String pageId = NotionPublishService.publishEnterprise(e);
    System.debug('═══════════════════════════════════════════════════════════');
    System.debug('✅ SMOKE TEST PASSED');
    System.debug('Page ID: ' + pageId);
    System.debug('Open Notion and verify the structure:');
    System.debug('  - 4 main toggles collapsible (Situation/Task/Action/Result)');
    System.debug('  - Sub-section headings are FLAT (no toggle arrow next to "Context")');
    System.debug('  - Content visible when main toggle is expanded');
    System.debug('═══════════════════════════════════════════════════════════');
} catch (Exception ex) {
    System.debug('❌ FAIL: ' + ex.getTypeName() + ' — ' + ex.getMessage());
    System.debug('Stack: ' + ex.getStackTraceString());
}
