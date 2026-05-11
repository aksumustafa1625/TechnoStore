/**
 * Publishes interview-prep entries to Notion as child pages.
 *
 * Two modes:
 *  - publish(StarEntry)            : single-page STAR with flat sections (legacy)
 *  - publishEnterprise(EnterpriseEntry): enterprise format with 4 STAR top-level toggles,
 *                                       each containing nested sub-toggles for sub-sections
 *
 * Enterprise structure per page:
 *  ▼ Situation
 *     ▼ Context | ▼ Problem
 *  ▼ Task
 *     ▼ Goal | ▼ Constraints | ▼ Success Criteria
 *  ▼ Action
 *     ▼ Approach | ▼ Implementation | ▼ Code | ▼ Screenshots (empty)
 *  ▼ Result
 *     ▼ Outcome | ▼ Trade-offs & Lessons Learned | ▼ References | ▼ Future Work
 *
 * Multi-call flow (due to Notion 2-level nesting limit per request):
 *  1. POST /v1/pages with title only → returns page id
 *  2. PATCH /v1/blocks/{page_id}/children with 4 empty main toggles → returns main toggle ids
 *  3. For each main toggle: PATCH children with sub-toggles + their content (2 levels deep)
 *
 * Auth: Bearer token from Notion_Config__c protected Custom Setting.
 * Notion API version: 2022-06-28.
 */
public with sharing class NotionPublishService {

    // ============================================================
    // Legacy StarEntry (kept for backward compatibility with smoke test)
    // ============================================================
    public class StarEntry {
        public String title;
        public String situation;
        public String taskText;
        public List<String> actions;
        public String result;
        public List<CodeSnippet> codeSnippets;
    }

    // ============================================================
    // Enterprise entry structure
    // ============================================================
    public class EnterpriseEntry {
        public String title;
        public SituationSection situation;
        public TaskSection task;
        public ActionSection action;
        public ResultSection result;
    }
    public class SituationSection {
        public String context;
        public String problem;
    }
    public class TaskSection {
        public String goal;
        public String constraints;
        public String successCriteria;
    }
    public class ActionSection {
        public String approach;
        public List<String> implementation;
        public List<CodeSnippet> codeSnippets;
    }
    public class ResultSection {
        public String outcome;
        public String tradeoffsAndLessons;
        public List<String> references;
        public String futureWork;
    }
    public class CodeSnippet {
        public String caption;
        public String language;
        public String code;
    }

    // ============================================================
    // Legacy publish (kept for smoke-test compatibility)
    // ============================================================
    public static String publish(StarEntry entry) {
        Notion_Config__c cfg = config();
        Map<String, Object> body = new Map<String, Object>{
            'parent' => new Map<String, String>{ 'page_id' => cfg.Parent_Page_Id__c },
            'properties' => new Map<String, Object>{
                'title' => new List<Object>{
                    new Map<String, Object>{ 'text' => new Map<String, String>{ 'content' => entry.title } }
                }
            },
            'children' => buildLegacyBlocks(entry)
        };
        HttpResponse resp = sendNotion('POST', 'https://api.notion.com/v1/pages', body, cfg.Token__c);
        if (!isSuccess(resp)) throw new NotionPublishException('Notion HTTP ' + resp.getStatusCode() + ': ' + resp.getBody());
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(resp.getBody())).get('id');
    }

    private static List<Object> buildLegacyBlocks(StarEntry entry) {
        List<Object> blocks = new List<Object>();
        blocks.add(heading2('Situation'));
        for (String p : splitParagraphs(entry.situation)) blocks.add(paragraph(p));
        blocks.add(heading2('Task'));
        for (String p : splitParagraphs(entry.taskText)) blocks.add(paragraph(p));
        blocks.add(heading2('Action'));
        if (entry.actions != null) for (String a : entry.actions) blocks.add(bulletItem(a));
        blocks.add(heading2('Result'));
        for (String p : splitParagraphs(entry.result)) blocks.add(paragraph(p));
        if (entry.codeSnippets != null && !entry.codeSnippets.isEmpty()) {
            blocks.add(heading2('Code'));
            for (CodeSnippet c : entry.codeSnippets) {
                if (!String.isBlank(c.caption)) blocks.add(paragraph(c.caption));
                blocks.add(codeBlock(c.code, c.language));
            }
        }
        return blocks;
    }

    // ============================================================
    // Enterprise publish (the new structure)
    // ============================================================
    public static String publishEnterprise(EnterpriseEntry entry) {
        Notion_Config__c cfg = config();
        String token = cfg.Token__c;

        // Step 1: Create page with title (no children yet)
        Map<String, Object> pageBody = new Map<String, Object>{
            'parent' => new Map<String, String>{ 'page_id' => cfg.Parent_Page_Id__c },
            'properties' => new Map<String, Object>{
                'title' => new List<Object>{
                    new Map<String, Object>{ 'text' => new Map<String, String>{ 'content' => entry.title } }
                }
            }
        };
        HttpResponse pageResp = sendNotion('POST', 'https://api.notion.com/v1/pages', pageBody, token);
        if (!isSuccess(pageResp)) throw new NotionPublishException('Page create: ' + pageResp.getBody());
        String pageId = (String) ((Map<String, Object>) JSON.deserializeUntyped(pageResp.getBody())).get('id');

        // Step 2: Append 4 empty main toggles → response gives us their ids
        List<Object> mainToggles = new List<Object>{
            buildToggle('Situation', new List<Object>()),
            buildToggle('Task', new List<Object>()),
            buildToggle('Action', new List<Object>()),
            buildToggle('Result', new List<Object>())
        };
        HttpResponse mainResp = sendNotion(
            'PATCH',
            'https://api.notion.com/v1/blocks/' + pageId + '/children',
            new Map<String, Object>{ 'children' => mainToggles },
            token
        );
        if (!isSuccess(mainResp)) throw new NotionPublishException('Main toggles: ' + mainResp.getBody());
        List<Object> mainResults = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(mainResp.getBody())).get('results');
        String situationId = (String) ((Map<String, Object>) mainResults.get(0)).get('id');
        String taskId      = (String) ((Map<String, Object>) mainResults.get(1)).get('id');
        String actionId    = (String) ((Map<String, Object>) mainResults.get(2)).get('id');
        String resultId    = (String) ((Map<String, Object>) mainResults.get(3)).get('id');

        // Step 3: Fill each main toggle with nested sub-toggles + content (4 PATCH calls)
        fillToggle(situationId, buildSituationChildren(entry.situation), token);
        fillToggle(taskId,      buildTaskChildren(entry.task),           token);
        fillToggle(actionId,    buildActionChildren(entry.action),       token);
        fillToggle(resultId,    buildResultChildren(entry.result),       token);

        return pageId;
    }

    private static void fillToggle(String blockId, List<Object> children, String token) {
        if (children == null || children.isEmpty()) return;
        HttpResponse resp = sendNotion(
            'PATCH',
            'https://api.notion.com/v1/blocks/' + blockId + '/children',
            new Map<String, Object>{ 'children' => children },
            token
        );
        if (!isSuccess(resp)) throw new NotionPublishException('Fill toggle ' + blockId + ': ' + resp.getBody());
    }

    private static List<Object> buildSituationChildren(SituationSection s) {
        List<Object> subs = new List<Object>();
        if (s != null) {
            subs.add(buildToggle('Context', paragraphsFrom(s.context)));
            subs.add(buildToggle('Problem', paragraphsFrom(s.problem)));
        }
        return subs;
    }

    private static List<Object> buildTaskChildren(TaskSection t) {
        List<Object> subs = new List<Object>();
        if (t != null) {
            subs.add(buildToggle('Goal',             paragraphsFrom(t.goal)));
            subs.add(buildToggle('Constraints',      paragraphsFrom(t.constraints)));
            subs.add(buildToggle('Success Criteria', paragraphsFrom(t.successCriteria)));
        }
        return subs;
    }

    private static List<Object> buildActionChildren(ActionSection a) {
        List<Object> subs = new List<Object>();
        if (a != null) {
            subs.add(buildToggle('Approach', paragraphsFrom(a.approach)));

            List<Object> implBlocks = new List<Object>();
            if (a.implementation != null) {
                for (String b : a.implementation) implBlocks.add(bulletItem(b));
            }
            subs.add(buildToggle('Implementation', implBlocks));

            List<Object> codeBlocks = new List<Object>();
            if (a.codeSnippets != null) {
                for (CodeSnippet c : a.codeSnippets) {
                    if (!String.isBlank(c.caption)) codeBlocks.add(paragraph(c.caption));
                    codeBlocks.add(codeBlock(c.code, c.language));
                }
            }
            subs.add(buildToggle('Code', codeBlocks));

            // Screenshots = empty toggle, user fills manually
            subs.add(buildToggle('Screenshots', new List<Object>()));
        }
        return subs;
    }

    private static List<Object> buildResultChildren(ResultSection r) {
        List<Object> subs = new List<Object>();
        if (r != null) {
            subs.add(buildToggle('Outcome',                      paragraphsFrom(r.outcome)));
            subs.add(buildToggle('Trade-offs & Lessons Learned', paragraphsFrom(r.tradeoffsAndLessons)));

            List<Object> refBlocks = new List<Object>();
            if (r.references != null) for (String ref : r.references) refBlocks.add(bulletItem(ref));
            subs.add(buildToggle('References', refBlocks));

            subs.add(buildToggle('Future Work', paragraphsFrom(r.futureWork)));
        }
        return subs;
    }

    private static List<Object> paragraphsFrom(String text) {
        List<Object> out = new List<Object>();
        for (String p : splitParagraphs(text)) out.add(paragraph(p));
        return out;
    }

    // ============================================================
    // Notion HTTP helper
    // ============================================================
    private static HttpResponse sendNotion(String method, String endpoint, Object body, String token) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Notion-Version', '2022-06-28');
        req.setHeader('Content-Type', 'application/json');
        if (body != null) req.setBody(JSON.serialize(body));
        req.setTimeout(60000);
        return new Http().send(req);
    }

    private static Boolean isSuccess(HttpResponse resp) {
        return resp.getStatusCode() >= 200 && resp.getStatusCode() < 300;
    }

    private static Notion_Config__c config() {
        Notion_Config__c cfg = Notion_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Token__c) || String.isBlank(cfg.Parent_Page_Id__c)) {
            throw new NotionPublishException('Notion_Config__c is missing Token__c or Parent_Page_Id__c.');
        }
        return cfg;
    }

    // ============================================================
    // Block builders
    // ============================================================
    private static Map<String, Object> buildToggle(String text, List<Object> children) {
        Map<String, Object> toggleData = new Map<String, Object>{
            'rich_text' => new List<Object>{ richText(text) }
        };
        if (children != null && !children.isEmpty()) {
            toggleData.put('children', children);
        }
        return new Map<String, Object>{
            'object' => 'block',
            'type'   => 'toggle',
            'toggle' => toggleData
        };
    }

    private static List<String> splitParagraphs(String text) {
        if (String.isBlank(text)) return new List<String>{ '(no content)' };
        List<String> out = new List<String>();
        for (String p : text.split('\n\n')) {
            if (String.isBlank(p)) continue;
            while (p.length() > 1900) {
                out.add(p.substring(0, 1900));
                p = p.substring(1900);
            }
            out.add(p);
        }
        return out;
    }

    private static Map<String, Object> heading2(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type'   => 'heading_2',
            'heading_2' => new Map<String, Object>{
                'rich_text' => new List<Object>{ richText(text) }
            }
        };
    }

    private static Map<String, Object> paragraph(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type'   => 'paragraph',
            'paragraph' => new Map<String, Object>{
                'rich_text' => new List<Object>{ richText(text) }
            }
        };
    }

    private static Map<String, Object> bulletItem(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type'   => 'bulleted_list_item',
            'bulleted_list_item' => new Map<String, Object>{
                'rich_text' => new List<Object>{ richText(text) }
            }
        };
    }

    private static Map<String, Object> codeBlock(String code, String language) {
        if (String.isBlank(language)) language = 'plain text';
        List<Object> richTextSegments = new List<Object>();
        String c = code == null ? '' : code;
        if (c.length() <= 1900) {
            richTextSegments.add(richText(c));
        } else {
            while (c.length() > 1900) {
                richTextSegments.add(richText(c.substring(0, 1900)));
                c = c.substring(1900);
            }
            if (c.length() > 0) richTextSegments.add(richText(c));
        }
        return new Map<String, Object>{
            'object' => 'block',
            'type'   => 'code',
            'code' => new Map<String, Object>{
                'rich_text' => richTextSegments,
                'language' => language
            }
        };
    }

    private static Map<String, Object> richText(String text) {
        if (text == null) text = '';
        if (text.length() > 1900) text = text.substring(0, 1900);
        return new Map<String, Object>{
            'type' => 'text',
            'text' => new Map<String, String>{ 'content' => text }
        };
    }

    public class NotionPublishException extends Exception {}
}
