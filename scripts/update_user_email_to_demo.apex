// Confirm user email post-verification
User u = [SELECT Id, Username, Email, FirstName, LastName FROM User WHERE Username = 'technostore-admin@example.com' LIMIT 1];
System.debug('Username: ' + u.Username);
System.debug('Email:    ' + u.Email);
System.debug('Name:     ' + u.FirstName + ' ' + u.LastName);
if (u.Email == 'demo-user@example.com') {
    System.debug('SUCCESS — approval emails now go to demo Gmail address.');
} else {
    System.debug('NOT YET — Email still shows ' + u.Email + '. Verification may still be pending.');
}
