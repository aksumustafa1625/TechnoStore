List<String> names = new List<String>(Invoice.SObjectType.getDescribe().fields.getMap().keySet());
names.sort();
System.debug('=== Invoice fields (' + names.size() + ') ===');
System.debug(String.join(names, ', '));
