# ADR-010: Notion API Multi-Call Orchestration for 3-Level Nested Toggles

## Status

**Accepted**

## Date

2026-05-11

## Author

Mustafa Aksu

## Context

TechnoStore's interview-preparation portfolio lives in Notion as **50 STAR-format entries** — each one a child page under the parent "TechnoStore Interview Prep" page. The required structural format per entry:

```
▼ Entry Title
   ├── ▼ Situation
   │      ├── ▼ Context
   │      │      └── [paragraphs]
   │      └── ▼ Problem
   │             └── [paragraphs]
   ├── ▼ Task
   │      ├── ▼ Goal
   │      ├── ▼ Constraints
   │      └── ▼ Success Criteria
   ├── ▼ Action
   │      ├── ▼ Approach
   │      ├── ▼ Implementation
   │      ├── ▼ Code               (code blocks with language tags)
   │      └── ▼ Screenshots         (empty — user fills manually)
   └── ▼ Result
          ├── ▼ Outcome
          ├── ▼ Trade-offs & Lessons Learned
          ├── ▼ References          (bullet list of memory files + entry references)
          └── ▼ Future Work
```

This is **3 levels of nesting from the Notion page root**: Page → Main Toggle (Situation/Task/Action/Result) → Sub Toggle (Context/Problem/Goal/etc.) → Content blocks (paragraphs, bullets, code).

The **Notion API hard limit**: **two levels of nesting per single POST or PATCH request**. From the [official documentation](https://developers.notion.com/reference/post-page) for `POST /v1/pages`:

> "When creating a page, the `children` property of the request body can be used to populate the page with content. **Up to two levels of nested children are supported in a single request.**"

Same limit applies to `PATCH /v1/blocks/{block_id}/children` (append children).

This means: in a single API request, the deepest the JSON tree can go is `children → block.children → block.children.children` — three levels of object nesting, two levels of *new block* nesting. Our structural requirement (Page → MainToggle → SubToggle → Content) exceeds this in a single call.

Building the portfolio manually via Notion UI (50 entries × 13 sub-toggles each × paragraphs + code) was estimated at 20+ hours and not version-controllable. A programmatic approach is required.

## Decision

**Orchestrate the 3-level structure via 6 API calls per entry**:

1. **POST `/v1/pages`** with title only — returns page ID *(1 call)*
2. **PATCH `/v1/blocks/{page_id}/children`** appending 4 empty Main Toggles (Situation/Task/Action/Result) — response includes their block IDs *(1 call)*
3. **PATCH `/v1/blocks/{situation_id}/children`** with Situation's sub-toggles + their content (2-level nesting from Situation — allowed) *(1 call)*
4. **PATCH `/v1/blocks/{task_id}/children`** with Task's sub-toggles + content *(1 call)*
5. **PATCH `/v1/blocks/{action_id}/children`** with Action's sub-toggles + content + empty Screenshots toggle *(1 call)*
6. **PATCH `/v1/blocks/{result_id}/children`** with Result's sub-toggles + content *(1 call)*

Each of the four "fill main toggle" PATCH calls supplies one level of new blocks (sub-toggles) plus their content (paragraphs / bullets / code blocks) — that is two levels of nesting from the patched block, which is permitted.

Total: **6 callouts per entry × 50 entries = 300 Notion API calls**.

The Salesforce Apex 100-callout-per-execution governor limit forces splitting the publish work into **batch scripts of ≤10 entries each** (10 entries × 6 callouts = 60 callouts per script, safely under the limit). 50 entries / 2-3 entries per batch (with the deeper technical content per entry pushing batch sizes down toward 2) yields **~19 batch scripts** named `scripts/notion_enterprise_batch_1.apex` through `_19.apex`.

`NotionPublishService.publishEnterprise(EnterpriseEntry entry)` is the single orchestration entry point that performs all 6 calls per entry. Block construction helpers (`buildToggle()`, `paragraph()`, `bulletItem()`, `codeBlock()`, `richText()`) handle the Notion block schema serialization.

## Consequences

### Positive

- **3-level nested toggle structure is achievable** despite the 2-level single-request limit. The pattern works.
- **Portfolio generation cost** ≈ 12 hours content authoring + 20 minutes API runs vs 20+ hours manual UI clicking. ~40% time savings.
- **Idempotent batch scripts** — each `notion_enterprise_batch_N.apex` reports per-entry success/failure with page IDs. Failed entries can be re-run individually.
- **Version-controlled portfolio source** — the batch scripts are checked into `scripts/` in git. The Notion-side rendering is regeneratable from source, not a one-way write that loses provenance.
- **Reusable for future portfolio updates** — adding entry 51 after the next demo iteration is one more batch script invocation, not 30 minutes of UI clicking.
- **Code block syntax highlighting works** — Notion's `code` block type supports a `language` field; the `codeBlock(code, language)` helper sets `language=java/xml/sql/bash/markdown` per snippet so the rendered Notion page has proper syntax highlighting.

### Negative / Trade-offs

- **6 calls per entry × 50 entries** is API-chatty. Notion rate limit is ~3 requests per second average — 300 calls / 3 = ~100 seconds total network time alone if not throttled. Across 19 batches with 30-second per-batch elapsed, this is comfortable but not negligible.
- **No transactional rollback across calls** — if the 4th PATCH fails after the 1st-3rd succeeded, the Notion page has the first 3 toggles populated but not the 4th. Recovery requires manual cleanup or re-run with idempotency awareness.
- **The "Screenshots" toggle is intentionally empty** by the publisher — user must manually paste screenshots into Notion UI per entry. Trade-off: automated screenshot generation is out of scope; user inserts UI screenshots after the demo recording.
- **Batch size constraint forces 19 scripts** — repeated invocation chore. Mitigated by autonomous batching feedback memory: user pre-approved running all batches without per-batch confirmation.

## Alternatives Considered

### Alternative A — Use H3 sub-section headings inside main toggles (no nested toggles)

Considered initially. Rejected because:
- Loses the toggle expand/collapse UX for sub-sections — recruiter has to scroll past full content rather than skim section titles.
- User explicitly requested nested toggle structure for the portfolio.
- Heading-3 with `is_toggleable: true` exists in the Notion API but has the same 2-level nesting limit — does not solve the structural problem.

### Alternative B — Single POST per entry with 2-level structure (Page → Toggle → Content, no sub-toggles)

Rejected because:
- Loses the third-level structural breakdown (Context/Problem under Situation, Goal/Constraints/Success Criteria under Task). Each main toggle becomes a single dense paragraph collection.
- Less scannable; reviewers want to drill into specific sub-sections.

### Alternative C — Use Notion API "blocks/{id}/children" with deeper nesting via repeated PATCHes

This is what we did, but with an extra layer of indirection: instead of bundling sub-toggle + content in one PATCH per main toggle, do one PATCH per sub-toggle. Rejected because:
- Multiplies call count by ~3x (each main toggle has 2-4 sub-toggles; PATCHing each individually = ~12 calls per entry instead of 4).
- Hits the Apex 100-callout-per-execution limit much faster — would require ~3 entries per batch and ~17 batch scripts (similar pain, more overhead).
- The current "2 levels per PATCH" approach is the sweet spot: enough nesting per call to be efficient, within the API limit.

### Alternative D — Use Notion Markdown import (Notion supports converting Markdown to native blocks)

Considered. Rejected because:
- Markdown import is a manual UI action (drag-drop or paste); cannot be triggered via API.
- Markdown does not have native toggle syntax — would lose the entire structural element that is the point.
- Round-trip is lossy: Notion's MD export doesn't perfectly preserve toggle hierarchies.

### Alternative E — Build a custom Notion Internal Integration with elevated nesting capability

Notion's API limits are at the platform level, not per-integration. Not achievable.

### Alternative F — Use a different documentation tool (GitBook, Confluence, MDX site)

Considered. Rejected because:
- Notion was specifically chosen for: shareable public URL, recruiter-familiar UI, nested toggle UX, free tier sufficient for portfolio scale.
- GitBook / Confluence introduce platform dependencies the project doesn't otherwise have.
- Static MDX site (Docusaurus, Nextra) would be a separate project to maintain — out of scope for the demo phase.

## Implementation pattern (preserved for reuse)

The 6-call orchestration is encapsulated in `NotionPublishService.publishEnterprise()`:

```apex
public static String publishEnterprise(EnterpriseEntry entry) {
    // 1. POST /v1/pages with title only
    String pageId = createPage(entry.title);

    // 2. PATCH page/children with 4 empty main toggles; capture IDs
    Map<String, String> toggleIds = appendMainToggles(pageId);

    // 3-6. PATCH each main toggle with sub-toggles + content (2 levels deep)
    fillToggle(toggleIds.get('Situation'), buildSituationChildren(entry.situation));
    fillToggle(toggleIds.get('Task'),      buildTaskChildren(entry.task));
    fillToggle(toggleIds.get('Action'),    buildActionChildren(entry.action));
    fillToggle(toggleIds.get('Result'),    buildResultChildren(entry.result));

    return pageId;
}
```

Each `buildXxxChildren()` returns `List<Object>` where each item is a toggle block with its `children` array populated with content blocks. This 2-level structure is what the per-toggle PATCH call accepts.

The pattern generalizes to any **3-level (or N-level)** programmatic Notion content with `N-1` API calls per entry — useful for future projects with deeper documentation structures.

## References

- **Memory**: `notion_portfolio_complete.md`, `feedback_autonomous_batching.md`
- **Notion portfolio entries**: 45 (Notion Documentation Pipeline — Apex → Notion API for AI-Assisted Portfolio Generation)
- **Code**: `force-app-services/main/default/classes/NotionPublishService.cls` (`publishEnterprise()` method)
- **Schema**: `force-app/main/default/objects/Notion_Config__c/` (credentials Custom Setting)
- **Batch scripts**: `scripts/notion_enterprise_batch_1.apex` through `_19.apex`
- **Smoke test**: `scripts/test_notion_publish.apex`
- **Related ADRs**: ADR-001 (Mule vs Apex matrix — Notion publish is Apex because it's a one-shot batch operation), ADR-004 (six-package layout — NotionPublishService lives in `force-app-services/`)
- **Notion API docs**: [Create a page](https://developers.notion.com/reference/post-page), [Append block children](https://developers.notion.com/reference/patch-block-children)
