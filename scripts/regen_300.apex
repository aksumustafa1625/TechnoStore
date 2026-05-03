GenerateContractPdfService.Request req = new GenerateContractPdfService.Request();
req.contractId = '800aj00002bkGsMAAU';
List<GenerateContractPdfService.Response> resp = GenerateContractPdfService.run(new List<GenerateContractPdfService.Request>{req});
System.debug('STATUS: ' + resp[0].status);
System.debug('MESSAGE: ' + resp[0].message);
