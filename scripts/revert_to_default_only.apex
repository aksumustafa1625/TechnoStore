// Revert IsComponentRequired back to false — keep only IsDefaultComponent=true
// This allows components to auto-add via Save & Exit without triggering "select child group" warnings
List<ProductRelatedComponent> children = [
    SELECT Id, ChildProduct.Name FROM ProductRelatedComponent
    WHERE ParentProductId='01taj00000Qp7IFAAZ'
];
for (ProductRelatedComponent c : children) {
    c.IsComponentRequired = false;
    c.IsDefaultComponent = true; // Keep default=true (so they're pre-checked)
}
update children;

// Set MinBundle/MaxBundle on the group — gives engine clear cardinality
update new ProductComponentGroup(Id='0y7aj000000CdC6AAK', MinBundleComponents=5, MaxBundleComponents=5);

System.debug('--- After update ---');
for (ProductRelatedComponent c : [
    SELECT ChildProduct.Name, IsDefaultComponent, IsComponentRequired
    FROM ProductRelatedComponent WHERE ParentProductId='01taj00000Qp7IFAAZ'
]) {
    System.debug(c.ChildProduct.Name + ' Default=' + c.IsDefaultComponent + ' Required=' + c.IsComponentRequired);
}
ProductComponentGroup grp = [SELECT MinBundleComponents, MaxBundleComponents FROM ProductComponentGroup WHERE Id='0y7aj000000CdC6AAK'];
System.debug('Group Min=' + grp.MinBundleComponents + ' Max=' + grp.MaxBundleComponents);
