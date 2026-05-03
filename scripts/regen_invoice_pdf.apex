// Regenerate the Invoice PDF + email for DOC-000000015 with new layout
AttachAndEmailInvoicePreview.Request req = new AttachAndEmailInvoicePreview.Request();
req.invoiceId = '3ttaj000000C2MDAA0';
AttachAndEmailInvoicePreview.run(new List<AttachAndEmailInvoicePreview.Request>{req});
System.debug('Invoice preview regenerated and emailed for DOC-000000015');
