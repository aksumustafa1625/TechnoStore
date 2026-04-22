# Salesforce CLM Contract Creation Error - Kesin Çözüm

## Sorun
```
We couldn't complete your request because the source object field mapped to the Name field is null or has an empty value.
```

## Kök Neden
CLM (Contract Lifecycle Management) yapılandırmasında, Order'dan Contract'a bir **Name field mapping** var ama:
- Contract objesi **Name alanına sahip değil** (sadece ContractNumber var)
- Mapping geçersiz bir alana işaret ediyor
- Bu yüzden Contract oluşturma başarısız oluyor

## ÇÖZÜM - Manuel Setup Yapılandırması (ZORUNLU)

Bu hata **sadece Salesforce Setup UI'dan düzeltilebilir**. Aşağıdaki adımları izleyin:

### Adım 1: CLM Field Mappings Sayfasını Açın
1. Salesforce'a giriş yapın
2. Sağ üst köşedeki **⚙️ Setup** ikonuna tıklayın
3. Quick Find'da `CLM` yazın
4. **Contract Lifecycle Management** > **Field Mappings** seçin

VEYA doğrudan bu linke gidin:
```
Setup > Contract Lifecycle Management > Field Mappings
```

### Adım 2: Order-to-Contract Mapping'i Bulun
1. Field Mappings sayfasında **Order to Contract** mapping'ini bulun
2. Eğer görünmüyorsa, "New Field Mapping" ile yeni bir tane oluşturmanız gerekebilir

### Adım 3: Name Field Mapping'ini Düzeltin

**Seçenek A: Name Mapping'ini Kaldırın (ÖNERİLEN)**
1. Order to Contract mapping'ini açın
2. Field mappings listesinde **Name** satırını bulun
3. Bu satırı **SİLİN** (çünkü Contract'ın Name alanı yok)
4. **Save** butonuna tıklayın

**Seçenek B: Description Field'ını Kullanın** 
Eğer Order'ın name'ini Contract'ta tutmak istiyorsanız:
1. Order to Contract mapping'ini açın  
2. Name field mapping'ini bulun
3. **Target Field** (Contract tarafı) değiştirin:
   - Eski: `Name` ❌ (geçersiz)
   - Yeni: `Description` ✅ (mevcut alan)
4. **Save** butonuna tıklayın

### Adım 4: Test Edin
1. Order sayfasına gidin (Order Number: 00000137 - "10 Computer Quote")
2. "Create Contract" butonuna tıklayın
3. Artık başarıyla Contract oluşturulmalı!

## Alternatif: Name__c Custom Field Kullanımı

Eğer Name__c custom field'ı org'da oluşturuldu ve görülebiliyorsa:
1. Setup > Object Manager > Contract > Fields & Relationships
2. Name__c field'ının varlığını kontrol edin
3. Field Mappings'de Target Field olarak `Name__c` kullanın

**NOT:** Deployment Name__c'yi oluşturdu ama Apex Schema'da görünmüyor. Bu genellikle şu anlama gelir:
- Field oluşturuldu ama henüz aktif değil
- Org'u refresh etmeniz gerekebilir
- Veya field permission sorunları olabilir

## Önemli Notlar

⚠️ **Bu düzeltme MUTLAKA Salesforce UI'dan yapılmalıdır**
- Metadata API veya CLI ile field mapping config değiştirilemez
- Custom Metadata Type kullanılmıyor (standart CLM config)
- Manuel UI değişikliği tek yol

⚠️ **Contract Object Standard Alanları**
- Contract objesi Name field'ına sahip DEĞİL
- Bunun yerine ContractNumber (auto-generated) kullanır
- Description veya custom field kullanılmalı

## Doğrulama

Başarılı contract oluşturulduktan sonra:
```sql
SELECT Id, ContractNumber, Description, AccountId, Account.Name
FROM Contract
WHERE AccountId IN (SELECT AccountId FROM Order WHERE OrderNumber = '00000137')
ORDER BY CreatedDate DESC
LIMIT 1
```

Eğer Description mapping kullandıysanız, Description field'ında "10 Computer Quote" göreceksiniz.

## Sorun Devam Ederse

1. CLM lisansınızın aktif olduğunu doğrulayın
2. User'ın CLM feature'larını kullanma yetkisi olduğunu kontrol edin
3. Order.Status = 'Activated' olduğunu doğrulayın (gerekli)
4. Order.EffectiveDate dolu olmalı

## İletişim

Bu adımları uyguladıktan sonra hala sorun yaşıyorsanız:
1. Field Mappings sayfasının ekran görüntüsünü alın
2. Tam hata mesajını kaydedin
3. Order ve Account bilgilerini paylaşın