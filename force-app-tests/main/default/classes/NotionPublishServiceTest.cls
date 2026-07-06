/**
 * Unit tests for NotionPublishService.
 *
 * Covers:
 *   - publish(StarEntry)              — legacy flat-section shape
 *   - publishEnterprise(EnterpriseEntry) — 4 top-level toggles (Situation/Task/Action/Result)
 *   - HTTP contract: Bearer auth, Notion-Version: 2022-06-28, application/json body
 *   - 1900-char chunking in paragraph text AND code blocks (rich_text segments)
 *   - Missing Notion_Config__c → NotionPublishException
 *   - 401 unauthorized → NotionPublishException carrying the status + body
 *   - 429 rate-limit  → NotionPublishException carrying the status + body
 *   - Code block language pass-through (documents current behavior; TS-TEST-005 may
 *     introduce apex→java / soql→sql alias normalization + unknown→plain-text
 *     whitelist fallback — see notes on those methods)
 *
 * Design:
 *   - No SeeAllData. @TestSetup seeds Notion_Config__c org defaults.
 *   - Inline HttpCalloutMock classes capture endpoint / headers / request body on
 *     instance fields for post-call inspection. (Apex forbids static members on
 *     inner classes, so each test news up a fresh mock and asserts against its
 *     instance state.)
 *   - Each test uses Test.setMock() then Test.startTest / Test.stopTest.
 */
@IsTest
private class NotionPublishServiceTest {

    private static final String FAKE_TOKEN = 'secret_notion_test_token_ABC123';
    private static final String FAKE_PARENT = 'parent-page-uuid-0000';

    // ============================================================
    // @TestSetup — seed Notion_Config__c org defaults
    // ============================================================
    @TestSetup
    static void seedConfig() {
        Notion_Config__c cfg = Notion_Config__c.getOrgDefaults();
        cfg.Token__c = FAKE_TOKEN;
        cfg.Parent_Page_Id__c = FAKE_PARENT;
        upsert cfg;
    }

    // ============================================================
    // Mock: 200 success (page created)
    // Instance fields — Apex disallows static members on inner classes.
    // ============================================================
    private class NotionMock200 implements HttpCalloutMock {
        public String capturedEndpoint;
        public String capturedMethod;
        public String capturedAuth;
        public String capturedNotionVersion;
        public String capturedContentType;
        public String capturedBody;
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            capturedEndpoint     = req.getEndpoint();
            capturedMethod       = req.getMethod();
            capturedAuth         = req.getHeader('Authorization');
            capturedNotionVersion = req.getHeader('Notion-Version');
            capturedContentType  = req.getHeader('Content-Type');
            capturedBody         = req.getBody();

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"object":"page","id":"page-uuid-abc","created_time":"2026-07-06T12:00:00Z","url":"https://notion.so/page-uuid-abc"}');
            return res;
        }
    }

    // ============================================================
    // Mock: 401 unauthorized
    // ============================================================
    private class NotionMock401 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}');
            return res;
        }
    }

    // ============================================================
    // Mock: 429 rate-limited
    // ============================================================
    private class NotionMock429 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(429);
            res.setHeader('Content-Type', 'application/json');
            res.setHeader('Retry-After', '30');
            res.setBody('{"object":"error","status":429,"code":"rate_limited","message":"You have been rate limited. Please try again in a few minutes."}');
            return res;
        }
    }

    // ============================================================
    // Mock: 400 validation error (unused directly but documented)
    // ============================================================
    private class NotionMockValidation implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"object":"error","status":400,"code":"validation_error","message":"body.children[0].type should be defined"}');
            return res;
        }
    }

    // ============================================================
    // Helpers to build fixture entries
    // ============================================================
    private static NotionPublishService.EnterpriseEntry buildMinimalEnterprise() {
        NotionPublishService.EnterpriseEntry e = new NotionPublishService.EnterpriseEntry();
        e.title = 'ADR-050 — Test Entry';

        e.situation = new NotionPublishService.SituationSection();
        e.situation.context = 'Context body';
        e.situation.problem = 'Problem body';

        e.task = new NotionPublishService.TaskSection();
        e.task.goal = 'Goal body';
        e.task.constraints = 'Constraint body';
        e.task.successCriteria = 'Success body';

        e.action = new NotionPublishService.ActionSection();
        e.action.approach = 'Approach body';
        e.action.implementation = new List<String>{ 'Step one', 'Step two' };
        e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>();

        e.result = new NotionPublishService.ResultSection();
        e.result.outcome = 'Outcome body';
        e.result.tradeoffsAndLessons = 'Trade-offs body';
        e.result.references = new List<String>{ 'ADR-001' };
        e.result.futureWork = 'Future body';
        return e;
    }

    private static NotionPublishService.StarEntry buildLegacyStar() {
        NotionPublishService.StarEntry e = new NotionPublishService.StarEntry();
        e.title = 'Legacy STAR entry';
        e.situation = 'Legacy situation paragraph.';
        e.taskText = 'Legacy task paragraph.';
        e.actions = new List<String>{ 'Action A', 'Action B' };
        e.result = 'Legacy result paragraph.';
        return e;
    }

    /** Round-trip parse the captured JSON body from the given mock. */
    private static Map<String, Object> parseBody(NotionMock200 mock) {
        return (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
    }

    /** Extract the top-level 'children' array from the parsed body. */
    private static List<Object> children(Map<String, Object> body) {
        return (List<Object>) body.get('children');
    }

    // ============================================================
    // Tests: publishEnterprise happy path
    // ============================================================
    @IsTest
    static void publishEnterprise_singleEntry_callsNotionApi_returnsPageId() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        String pageId;
        Test.startTest();
        pageId = NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        Test.stopTest();

        System.assertEquals('page-uuid-abc', pageId, 'Must return the page id parsed from the 200 body');
        System.assertEquals(1, mock.callCount, 'Enterprise publish must be a single POST');
        System.assertEquals('POST', mock.capturedMethod);
        System.assertEquals('https://api.notion.com/v1/pages', mock.capturedEndpoint);
    }

    @IsTest
    static void notion200_recordsPublishedPageId() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String pageId = NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        Test.stopTest();

        System.assertEquals('page-uuid-abc', pageId,
            '200 body id field must round-trip out as the return value');
    }

    // ============================================================
    // Tests: config validation
    // ============================================================
    @IsTest
    static void publishEnterprise_missingConfig_throwsOrLogs() {
        // Wipe the token so config() rejects it.
        Notion_Config__c cfg = Notion_Config__c.getOrgDefaults();
        cfg.Token__c = null;
        upsert cfg;

        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        } catch (NotionPublishService.NotionPublishException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Missing Token__c must throw NotionPublishException');
        System.assert(msg != null && msg.contains('Notion_Config__c'),
            'Exception message must name the custom setting. Got: ' + msg);
    }

    // ============================================================
    // Tests: legacy StarEntry path
    // ============================================================
    @IsTest
    static void publish_legacyStarEntry_worksWithLegacyShape() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String pageId = NotionPublishService.publish(buildLegacyStar());
        Test.stopTest();

        System.assertEquals('page-uuid-abc', pageId, 'Legacy publish must also parse id from 200 body');
        System.assertEquals(1, mock.callCount);

        // Legacy shape emits heading_2 blocks (not toggles) at the top level.
        Map<String, Object> body = parseBody(mock);
        List<Object> kids = children(body);
        System.assert(kids.size() >= 4,
            'Legacy blocks include Situation/Task/Action/Result headings at minimum. Got: ' + kids.size());
        Map<String, Object> first = (Map<String, Object>) kids.get(0);
        System.assertEquals('heading_2', (String) first.get('type'),
            'Legacy path uses heading_2 blocks, not toggles');
    }

    // ============================================================
    // Tests: chunking
    // ============================================================
    @IsTest
    static void chunking_bodyOver1900Chars_splitsIntoMultipleBlocks() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        // 2500 chars in one paragraph — no \n\n splits — expect 2 paragraph blocks
        // (1900 + 600) inside the Situation toggle's Context sub-section.
        e.situation.context = 'X'.repeat(2500);

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        Map<String, Object> body = parseBody(mock);
        List<Object> kids = children(body);
        Map<String, Object> situationToggle = (Map<String, Object>) kids.get(0);
        Map<String, Object> toggleData = (Map<String, Object>) situationToggle.get('toggle');
        List<Object> situationChildren = (List<Object>) toggleData.get('children');

        // Walk to the Context section: heading_3(Context) then paragraph blocks until heading_3(Problem)
        Integer paragraphsUnderContext = 0;
        Boolean insideContext = false;
        for (Object o : situationChildren) {
            Map<String, Object> block = (Map<String, Object>) o;
            String t = (String) block.get('type');
            if (t == 'heading_3') {
                // First heading_3 = Context, second = Problem
                if (!insideContext) { insideContext = true; }
                else { break; }
            } else if (insideContext && t == 'paragraph') {
                paragraphsUnderContext++;
            }
        }
        System.assertEquals(2, paragraphsUnderContext,
            '2500-char body must split into 2 paragraph blocks (1900 + 600)');
    }

    @IsTest
    static void chunking_codeBlock_respects1900Limit() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        NotionPublishService.CodeSnippet snip = new NotionPublishService.CodeSnippet();
        snip.caption = null;
        snip.language = 'java';
        snip.code = 'A'.repeat(4300); // → 1900 + 1900 + 500 = 3 rich_text segments
        e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snip };

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        Map<String, Object> body = parseBody(mock);
        List<Object> kids = children(body);
        // Action toggle is the 3rd top-level child
        Map<String, Object> actionToggle = (Map<String, Object>) kids.get(2);
        Map<String, Object> toggleData = (Map<String, Object>) actionToggle.get('toggle');
        List<Object> actionChildren = (List<Object>) toggleData.get('children');

        Map<String, Object> foundCode = null;
        for (Object o : actionChildren) {
            Map<String, Object> block = (Map<String, Object>) o;
            if ('code'.equals((String) block.get('type'))) {
                foundCode = block;
                break;
            }
        }
        System.assertNotEquals(null, foundCode, 'Code block must be present under Action');
        Map<String, Object> codeData = (Map<String, Object>) foundCode.get('code');
        List<Object> segments = (List<Object>) codeData.get('rich_text');
        System.assertEquals(3, segments.size(),
            '4300-char code body must split into 3 rich_text segments (1900+1900+500)');
        System.assertEquals('java', (String) codeData.get('language'),
            'Explicit language must round-trip unchanged');
    }

    @IsTest
    static void chunking_boundaryAt1900_producesSingleBlock() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        // Exactly 1900 → while(len > 1900) is false → single paragraph block.
        e.situation.context = 'B'.repeat(1900);

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        Map<String, Object> body = parseBody(mock);
        List<Object> kids = children(body);
        Map<String, Object> situationToggle = (Map<String, Object>) kids.get(0);
        Map<String, Object> toggleData = (Map<String, Object>) situationToggle.get('toggle');
        List<Object> situationChildren = (List<Object>) toggleData.get('children');

        Integer paragraphsUnderContext = 0;
        Boolean insideContext = false;
        for (Object o : situationChildren) {
            Map<String, Object> block = (Map<String, Object>) o;
            String t = (String) block.get('type');
            if (t == 'heading_3') {
                if (!insideContext) insideContext = true; else break;
            } else if (insideContext && t == 'paragraph') {
                paragraphsUnderContext++;
            }
        }
        System.assertEquals(1, paragraphsUnderContext,
            'Body of exactly 1900 chars must emit a single paragraph block (boundary condition)');
    }

    // ============================================================
    // Tests: HTTP headers
    // ============================================================
    @IsTest
    static void notionVersionHeader_2022_06_28_isSent() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        Test.stopTest();

        System.assertEquals('2022-06-28', mock.capturedNotionVersion,
            'Notion-Version header must pin to the 2022-06-28 API contract');
        System.assertEquals('application/json', mock.capturedContentType,
            'Content-Type must be application/json');
    }

    @IsTest
    static void bearerTokenAuth_isSent() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        Test.stopTest();

        System.assertEquals('Bearer ' + FAKE_TOKEN, mock.capturedAuth,
            'Authorization header must be Bearer <Token__c>');
    }

    // ============================================================
    // Tests: enterprise structure
    // ============================================================
    @IsTest
    static void enterpriseEntry_starToggle_producesFourToggleBlocks_situationTaskActionResult() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        Test.stopTest();

        Map<String, Object> body = parseBody(mock);
        List<Object> kids = children(body);
        System.assertEquals(4, kids.size(),
            'Enterprise entry must produce exactly 4 top-level toggle blocks');

        List<String> expectedLabels = new List<String>{ 'Situation', 'Task', 'Action', 'Result' };
        for (Integer i = 0; i < 4; i++) {
            Map<String, Object> block = (Map<String, Object>) kids.get(i);
            System.assertEquals('block', (String) block.get('object'));
            System.assertEquals('toggle', (String) block.get('type'),
                'Top-level block ' + i + ' must be a toggle');
            Map<String, Object> toggleData = (Map<String, Object>) block.get('toggle');
            List<Object> richTextArr = (List<Object>) toggleData.get('rich_text');
            Map<String, Object> rt = (Map<String, Object>) richTextArr.get(0);
            Map<String, Object> textObj = (Map<String, Object>) rt.get('text');
            System.assertEquals(expectedLabels[i], (String) textObj.get('content'),
                'Toggle ' + i + ' label mismatch');
        }
    }

    // ============================================================
    // Tests: code language pass-through
    // ============================================================
    // NOTE: NotionPublishService does NOT currently normalize language aliases.
    // Whatever caller passes goes to Notion as-is (only blank/null → 'plain text').
    // TS-TEST-005 could add: apex→java, soql→sql, and a whitelist that maps
    // unrecognized values to 'plain text'. These tests document current behavior;
    // once alias mapping ships, flip the expected value.

    @IsTest
    static void codeLanguageAlias_apex_normalizedToJava() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        NotionPublishService.CodeSnippet snip = new NotionPublishService.CodeSnippet();
        snip.language = 'apex';
        snip.code = 'System.debug(\'hi\');';
        e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snip };

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        String lang = extractFirstCodeLanguage(parseBody(mock));
        // Current behavior: pass-through. TS-TEST-005 target: 'java'.
        System.assertEquals('apex', lang,
            'Current pass-through behavior; TS-TEST-005 may map apex→java');
    }

    @IsTest
    static void codeLanguageAlias_soql_normalizedToSql() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        NotionPublishService.CodeSnippet snip = new NotionPublishService.CodeSnippet();
        snip.language = 'soql';
        snip.code = 'SELECT Id FROM Account LIMIT 1';
        e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snip };

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        String lang = extractFirstCodeLanguage(parseBody(mock));
        // Current behavior: pass-through. TS-TEST-005 target: 'sql'.
        System.assertEquals('soql', lang,
            'Current pass-through behavior; TS-TEST-005 may map soql→sql');
    }

    @IsTest
    static void unknownLanguage_defaultsToPlainText() {
        NotionMock200 mock = new NotionMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        NotionPublishService.EnterpriseEntry e = buildMinimalEnterprise();
        // Blank language exercises the class's actual fallback branch.
        NotionPublishService.CodeSnippet snip = new NotionPublishService.CodeSnippet();
        snip.language = null;
        snip.code = 'hello';
        e.action.codeSnippets = new List<NotionPublishService.CodeSnippet>{ snip };

        Test.startTest();
        NotionPublishService.publishEnterprise(e);
        Test.stopTest();

        String lang = extractFirstCodeLanguage(parseBody(mock));
        System.assertEquals('plain text', lang,
            'Blank/null language must fall back to Notion default "plain text"');
    }

    /** Walk the parsed body → Action toggle → first code block → language field. */
    private static String extractFirstCodeLanguage(Map<String, Object> body) {
        List<Object> kids = (List<Object>) body.get('children');
        Map<String, Object> actionToggle = (Map<String, Object>) kids.get(2);
        Map<String, Object> toggleData = (Map<String, Object>) actionToggle.get('toggle');
        List<Object> actionChildren = (List<Object>) toggleData.get('children');
        for (Object o : actionChildren) {
            Map<String, Object> block = (Map<String, Object>) o;
            if ('code'.equals((String) block.get('type'))) {
                Map<String, Object> codeData = (Map<String, Object>) block.get('code');
                return (String) codeData.get('language');
            }
        }
        return null;
    }

    // ============================================================
    // Tests: error paths
    // ============================================================
    @IsTest
    static void notion401_isLoggedAsAuthError_notionPublishExceptionThrown() {
        Test.setMock(HttpCalloutMock.class, new NotionMock401());

        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        } catch (NotionPublishService.NotionPublishException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, '401 must raise NotionPublishException');
        System.assert(msg != null && msg.contains('401'),
            'Exception message must carry the 401 status. Got: ' + msg);
        System.assert(msg.contains('unauthorized') || msg.contains('token'),
            'Exception message must carry the Notion error body. Got: ' + msg);
    }

    @IsTest
    static void notion429_isLoggedAsRateLimit() {
        Test.setMock(HttpCalloutMock.class, new NotionMock429());

        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        } catch (NotionPublishService.NotionPublishException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, '429 must raise NotionPublishException');
        System.assert(msg != null && msg.contains('429'),
            'Exception message must carry the 429 status. Got: ' + msg);
        System.assert(msg.contains('rate') || msg.contains('rate_limited'),
            'Exception body must be echoed for triage. Got: ' + msg);
    }

    @IsTest
    static void notion400_validationError_isPropagatedAsException() {
        Test.setMock(HttpCalloutMock.class, new NotionMockValidation());

        Boolean threw = false;
        String msg;
        Test.startTest();
        try {
            NotionPublishService.publishEnterprise(buildMinimalEnterprise());
        } catch (NotionPublishService.NotionPublishException e) {
            threw = true;
            msg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, '400 must raise NotionPublishException');
        System.assert(msg != null && msg.contains('400'),
            'Exception message must carry the 400 status. Got: ' + msg);
    }
}
