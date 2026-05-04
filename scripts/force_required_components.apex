// Make all 5 child components REQUIRED so they auto-add when bundle is added to quote
List<ProductRelatedComponent> children = [
    SELECT Id, ChildProduct.Name, IsComponentRequired, IsDefaultComponent
    FROM ProductRelatedComponent
    WHERE ParentProductId = '01taj00000Qp7IFAAZ'
];
System.debug('Found ' + children.size() + ' children');
for (ProductRelatedComponent c : children) {
    c.IsComponentRequired = true;
    c.IsDefaultComponent = true;
}
update children;

for (ProductRelatedComponent c : [
    SELECT Id, ChildProduct.Name, IsComponentRequired, IsDefaultComponent
    FROM ProductRelatedComponent WHERE ParentProductId='01taj00000Qp7IFAAZ'
]) {
    System.debug(c.ChildProduct.Name + ' Required=' + c.IsComponentRequired + ' Default=' + c.IsDefaultComponent);
}
