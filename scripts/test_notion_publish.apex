// Smoke test: push one STAR entry to Notion and verify the page id comes back.

NotionPublishService.StarEntry e = new NotionPublishService.StarEntry();
e.title = '🧪 Smoke Test — Notion API Connection';
e.situation = 'Connecting Salesforce to Notion via API integration for STAR-format interview prep content publishing.';
e.taskText = 'Verify the Apex-to-Notion callout pipeline works end to end before pushing 22 real entries.';
e.actions = new List<String>{
    'Created Notion_Config__c protected Custom Setting with Token + Parent Page Id fields',
    'Deployed Remote Site Setting for api.notion.com',
    'Wrote NotionPublishService.cls — Apex HTTP callout posting child pages with structured H2 sections',
    'Granted FLS via Notion_Publisher_Access permission set'
};
e.result = 'Successful POST returns Notion page id, the page appears as a child under TechnoStore Interview Prep parent page. Pipeline is production-ready for the 22-entry bulk publish.';

try {
    String pageId = NotionPublishService.publish(e);
    System.debug('SUCCESS — created Notion page: ' + pageId);
} catch (Exception ex) {
    System.debug('FAIL: ' + ex.getTypeName() + ' — ' + ex.getMessage());
}
