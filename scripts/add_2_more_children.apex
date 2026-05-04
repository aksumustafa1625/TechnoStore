// Add 2 new One-Time office accessories to Home Office Bundle
// ErgoMouse Vertical (01taj00000QnnmXAAR) + WebCam Pro 4K Studio (01taj00000Qnnm1AAB)

Id parentBundleId = '01taj00000Qp7IFAAZ';
Id officeGroupId = '0y7aj000000CdC6AAK';

List<ProductRelatedComponent> newChildren = new List<ProductRelatedComponent>{
    new ProductRelatedComponent(
        ParentProductId = parentBundleId,
        ChildProductId = '01taj00000QnnmXAAR', // ErgoMouse Vertical
        ProductComponentGroupId = officeGroupId,
        Quantity = 1,
        IsDefaultComponent = true,
        IsComponentRequired = false,
        DoesBundlePriceIncludeChild = true,
        ProductRelationshipTypeId = '0yoaj000000MpThAAK',
        Sequence = 6
    ),
    new ProductRelatedComponent(
        ParentProductId = parentBundleId,
        ChildProductId = '01taj00000Qnnm1AAB', // WebCam Pro 4K Studio
        ProductComponentGroupId = officeGroupId,
        Quantity = 1,
        IsDefaultComponent = true,
        IsComponentRequired = false,
        DoesBundlePriceIncludeChild = true,
        ProductRelationshipTypeId = '0yoaj000000MpThAAK',
        Sequence = 7
    )
};
insert newChildren;

System.debug('Inserted ' + newChildren.size() + ' new children');
for (ProductRelatedComponent c : [
    SELECT ChildProduct.Name, IsDefaultComponent, Sequence
    FROM ProductRelatedComponent WHERE ParentProductId=:parentBundleId
    ORDER BY Sequence
]) {
    System.debug(c.Sequence + '. ' + c.ChildProduct.Name + ' default=' + c.IsDefaultComponent);
}
