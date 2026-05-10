// Search global describe for category-related objects
for (String objName : Schema.getGlobalDescribe().keySet()) {
    String lower = objName.toLowerCase();
    if (lower.contains('categorydisqualification') || lower.contains('categoryqualification')) {
        System.debug('Found: ' + objName);
    }
}
