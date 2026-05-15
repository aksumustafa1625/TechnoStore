try {
    ContentVersion cv = [SELECT Id, VersionData, Title FROM ContentVersion WHERE Id = '068aj00000InLwzAAF' LIMIT 1];
    String pdfBase64 = EncodingUtil.base64Encode(cv.VersionData);

    Map<String, Object> envelope = new Map<String, Object>{
        'emailSubject' => 'Test Signature Request - ' + cv.Title,
        'emailBlurb' => 'Please sign this contract.',
        'status' => 'sent',
        'documents' => new List<Object>{
            new Map<String, Object>{
                'documentBase64' => pdfBase64,
                'name' => cv.Title + '.pdf',
                'fileExtension' => 'pdf',
                'documentId' => '1'
            }
        },
        'recipients' => new Map<String, Object>{
            'signers' => new List<Object>{
                new Map<String, Object>{
                    'email' => 'demo@technostore.example',
                    'name' => 'Meliha Sari',
                    'recipientId' => '1',
                    'routingOrder' => '1',
                    'tabs' => new Map<String, Object>{
                        'signHereTabs' => new List<Object>{
                            new Map<String, Object>{
                                'documentId' => '1',
                                'pageNumber' => '1',
                                'xPosition' => '100',
                                'yPosition' => '100'
                            }
                        }
                    }
                }
            }
        }
    };

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:DocuSign/restapi/v2.1/accounts/47481170/envelopes');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    req.setBody(JSON.serialize(envelope));
    req.setTimeout(120000);

    HttpResponse res = new Http().send(req);
    System.debug('=STATUS=' + res.getStatusCode());
    System.debug('=RESPONSE=' + res.getBody());
} catch (Exception e) {
    System.debug('=EXCEPTION=' + e.getTypeName() + ' | ' + e.getMessage());
    System.debug('=STACK=' + e.getStackTraceString());
}
