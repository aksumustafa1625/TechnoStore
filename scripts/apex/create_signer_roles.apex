// Create SignerRole records via ESignatureConfig (ConfigType=SignerRoles, GroupType=AnchorTabSetting)
List<ESignatureConfig> roles = new List<ESignatureConfig>{
    new ESignatureConfig(
        MasterLabel='Customer Signer', DeveloperName='Customer_Signer',
        ConfigType='SignerRoles', GroupType='AnchorTabSetting',
        ConfigValue='Customer Signer', Vendor='DocuSign',
        Description='External customer signing the contract'
    ),
    new ESignatureConfig(
        MasterLabel='Internal Approver', DeveloperName='Internal_Approver',
        ConfigType='SignerRoles', GroupType='AnchorTabSetting',
        ConfigValue='Internal Approver', Vendor='DocuSign',
        Description='Internal company representative'
    ),
    new ESignatureConfig(
        MasterLabel='Witness', DeveloperName='Witness',
        ConfigType='SignerRoles', GroupType='AnchorTabSetting',
        ConfigValue='Witness', Vendor='DocuSign',
        Description='Witness to the signing'
    ),
    new ESignatureConfig(
        MasterLabel='CC Recipient', DeveloperName='CC_Recipient',
        ConfigType='SignerRoles', GroupType='AnchorTabSetting',
        ConfigValue='CC Recipient', Vendor='DocuSign',
        Description='Carbon copy recipient (no signature required)'
    )
};
insert roles;
for (ESignatureConfig r : roles) {
    System.debug(r.Id + ' | ' + r.MasterLabel);
}
System.debug('Inserted ' + roles.size() + ' Signer Role records');
