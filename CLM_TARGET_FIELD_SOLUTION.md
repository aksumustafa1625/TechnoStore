# CLM Target Object Custom Field Name Çözümü

## Hata Mesajı
```
We couldn't create or update the Context Use Case Mapping object because the target object custom field name is missing. Specify a valid value and try again.
```

## Sorun
"Target Object Custom Field Name" alanı boş bırakılamıyor. CLM bir Contract field'ı bekliyor.

## ✅ ÇÖZÜM: Description Field'ını Kullanın

### ADIM 1: Target Object Custom Field Name Doldurun
Ekran görüntüsünde gösterilen formdaki "**Target Object Custom Field Name**" alanına şunu yazın:

```
Description
```

### ADIM 2: Save Edin
1. "Target Object Custom Field Name" = `Description`
2. Diğer alanlar dolu olmalı:
   - Reference Object Name: Order
   - Target Object Name: Contract
   - Context Definition Name: ContractsContextDefinition
   - Mapping Type: Persistence
   - Mapping Name: OrderToCntrPersistenceMapping
   - Use Case Type: Create Contract or Update Contract
3. **Save** butonuna tıklayın

## Neden Description?

Contract objesinde Name alanı yok, bu yüzden alternatif bir alan kullanmalıyız:
- **Description**: Mevcut, text alan, Order.Name değerini saklayabilir
- Name__c: Deploy ettik ama org'da aktif görünmüyor
- ContractNumber: Auto-generated, map edilemez

## Test Etme

1. Mapping'i Description ile kaydedin
2. Order sayfasına gidin (Order #00000137)
3. "Create Contract" tıklayın
4. Contract oluşturulacak ve Description field'ında "10 Computer Quote" göreceksiniz

## Alternatif Field'lar

Eğer Description kullanmak istemiyorsanız, Contract'ta kullanabileceğiniz başka text field'lar:
- `Special Terms` (SpecialTerms)
- `Customer Signed Title` (CustomerSignedTitle)
- Veya kendi custom field'ınızı oluşturun

## Doğrulama Query

Contract oluştuktan sonra kontrol edin:
```sql
SELECT Id, ContractNumber, Description, AccountId, Account.Name
FROM Contract
WHERE AccountId IN (
    SELECT AccountId FROM Order WHERE OrderNumber = '00000137'
)
ORDER BY CreatedDate DESC
LIMIT 1
```

Description field'ında "10 Computer Quote" görmelisiniz.