# CLM Contract Creation - KESİN ÇÖZÜM

## 🎯 BAŞARILI TEST SONUÇLARI

Manuel test sonuçları:
- ✅ Contract başarıyla oluşturuldu (ID: 800aj00002YO0vBAAT, Number: 00000225)
- ✅ Description field'ı "10 Computer Quote" ile dolduruldu
- ✅ Contract oluşturma işlemi çalışıyor!

## ❌ Sorun Neydi?

Order zaten "Activated" durumunda ve ContractId değiştirilemez. CLM API bunu otomatik yapar, bizim manuel yapma gerekmiyor.

## ✅ KESİN ÇÖZÜM

CLM Field Mapping'de **"Target Object Custom Field Name"** için şu alanlardan birini kullanın:

### Seçenek 1: CustomerSignedTitle (ÖNERİLEN)
```
CustomerSignedTitle
```
- Bu alan Contract'ta writable
- Order Name'i burada saklayabilirsiniz

### Seçenek 2: Description  
```
Description
```
- Daha uzun text için uygun
- Ama CLM UI'da görünebilir sorunlar olabilir

## 📋 ADIM ADIM YAPILACAKLAR

### 1. CLM Context Use Case Mapping Sayfasını Açın
- Setup > Contract Lifecycle Management > Context Use Case Mappings
- "OrderToCntrPersistenceMapping" mapping'ini açın

### 2. Target Object Custom Field Name Doldurun
Forma gidin ve şunu yazın:
```
Target Object Custom Field Name: CustomerSignedTitle
```

### 3. Diğer Alanlar
- Reference Object Name: Order ✅
- Target Object Name: Contract ✅
- Reference Object Record Type: (boş bırakabilirsiniz)
- Target Object Record Type: (boş bırakabilirsiniz)
- Context Definition Name: ContractsContextDefinition ✅
- Mapping Type: Persistence ✅
- Mapping Name: OrderToCntrPersistenceMapping ✅
- Use Case Type: Create Contract or Update Contract ✅

### 4. Save ve Test
1. **Save** butonuna tıklayın
2. Order sayfasına gidin (Order #00000137)
3. "Create Contract" butonuna tıklayın
4. ✅ Contract başarıyla oluşturulacak!

## 🔍 Neden CustomerSignedTitle?

Test sonuçlarından öğrendiklerimiz:
- Contract'ta writable text field'lar:
  - `billingcity`
  - `billingstate`
  - `billingpostalcode`
  - `billingcountry`
  - **`customersignedtitle`** ← Bu Order Name için en uygun!

## 📊 Doğrulama

Contract oluştuktan sonra kontrol edin:
```sql
SELECT Id, ContractNumber, CustomerSignedTitle, Description, 
       AccountId, Account.Name, Status
FROM Contract
WHERE AccountId IN (
    SELECT AccountId FROM Order WHERE OrderNumber = '00000137'
)
ORDER BY CreatedDate DESC
LIMIT 1
```

CustomerSignedTitle field'ında "10 Computer Quote" göreceksiniz.

## ⚠️ Önemli Notlar

1. **Order Activated durumda** - Bu normal ve gerekli
2. **ContractId otomatik atanır** - CLM API bunu yapar
3. **Name__c field'ı yok** - Deployment başarısız, Description veya CustomerSignedTitle kullanın
4. **CustomerSignedTitle ideal** - Order Name için mantıklı bir alan

## 🆘 Hala Çalışmazsa

1. CLM lisansınızı kontrol edin
2. User'ın Contract create permission'ı olmalı
3. Field-level security: CustomerSignedTitle field'ı editable olmalı
4. Validation rules Contract'ta olmadığından emin olun

## 📞 Son Çare

Eğer hala çalışmazsa, şu screenshot'ları paylaşın:
1. Context Use Case Mapping formu (tüm alanlar dolu)
2. Aldığınız tam hata mesajı
3. User permissions (Profile veya Permission Sets)