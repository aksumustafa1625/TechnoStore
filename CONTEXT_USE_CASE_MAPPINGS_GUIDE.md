sen # Context Use Case Mappings - DETAYLI KILAVUZ

## 🎯 DOĞRU YER BURASI!

Tarayıcınızda **Setup > Context Use Case Mappings** sayfası açıldı.
Bu, CLM Contract oluşturma mapping'lerinin bulunduğu **DOĞRU SAYFA**.

## 📋 ADIM ADIM TALİMATLAR

### ADIM 1: Mapping Listesini Görün

Sayfada bir **tablo/liste** göreceksiniz. Şunlara benzer sütunlar olacak:
- **Mapping Name** (Mapping Adı)
- **Context Definition** (Context Tanımı)
- **Reference Object** (Kaynak Obje)
- **Target Object** (Hedef Obje)
- **Use Case Type** (Kullanım Tipi)
- **Actions** (İşlemler - Edit/Delete butonları)

### ADIM 2: Order-to-Contract Mapping Bulun

Tabloda şu satırı arayın:
```
Mapping Name: OrderToCntrPersistenceMapping
Context Definition: Custom_ContractsContext veya ContractsContextDefinition
Reference Object: Order
Target Object: Contract
Use Case Type: Create Contract or Update Contract
```

### ADIM 3: Mapping'i Açın

1. Bu satırın sağında **Edit** veya **View** butonu olmalı
2. Butona tıklayın
3. Yeni bir sayfa/form açılacak

### ADIM 4: Form Alanlarını Kontrol Edin

Açılan formda şu alanları göreceksiniz:
- Reference Object Name: Order
- Target Object Name: Contract
- **Target Object Custom Field Name**: ← **BURASI ÖNEMLİ!**
- Context Definition Name: Custom_ContractsContext
- Mapping Type: Persistence
- Use Case Type: Create Contract or Update Contract

### ADIM 5: Target Object Custom Field Name Düzeltin

**"Target Object Custom Field Name"** alanında ne yazıyor?
- Eğer **"Name"** yazıyorsa ❌ - Bunu değiştirin!
- Eğer **boş** ise - Doldurun!

**Şunu yazın:**
```
Description
```

VEYA

```
CustomerSignedTitle
```

### ADIM 6: Save Edin

1. **Save** butonuna tıklayın
2. Sayfanın kapanmasını bekleyin
3. Başarılı mesajı göreceksiniz

### ADIM 7: Test Edin!

1. Order sayfasına gidin (Order #00000137)
2. "Create Contract" butonuna tıklayın
3. ✅ Artık çalışacak!

## 🔍 Eğer Mapping Bulamazsanız

### ARAMA ÖNERİLERİ:

1. **Sayfa filtreleri kontrol edin**
   - "Show All" veya "Tümünü Göster" seçeneği var mı?
   - Herhangi bir filtre aktif mi?

2. **Aramayı kullanın**
   - Sayfada bir Search/Arama kutusu varsa
   - "Order" veya "Contract" yazın

3. **Yeni Mapping Oluşturun**
   - "New" veya "New Mapping" butonu varsa tıklayın
   - Aşağıdaki bilgilerle doldurun:

## 📝 Yeni Mapping Oluşturma (Gerekirse)

Eğer hiç mapping yoksa, "New" butonuna tıklayın ve şunları doldurun:

```
Mapping Name: OrderToContractMapping
Context Definition: Custom_ContractsContext
Reference Object Name: Order
Target Object Name: Contract
Target Object Custom Field Name: Description
Mapping Type: Persistence  
Use Case Type: Create Contract or Update Contract
```

## ⚠️ ÖNEMLİ NOTLAR

1. **"Target Object Custom Field Name" BOŞ BIRAKILAMAZ**
   - Mutlaka bir değer girmelisiniz
   - "Description" veya "CustomerSignedTitle" kullanın
   - "Name" KULLANMAYIN (Contract'ta yok!)

2. **Context Definition**
   - Custom_ContractsContext olmalı
   - Eğer ContractsContextDefinition varsa onu seçin

3. **Mapping Type**
   - Persistence olmalı
   - Diğer seçenekler: Transition, Query (bunları seçmeyin)

## 📸 Ekran Görüntüsü Alın

Eğer hala bulamıyorsanız:
1. Context Use Case Mappings sayfasının ekran görüntüsünü alın
2. Bana gösterin
3. Beraber bulalım

## 🎉 Başarı Sonrası

Mapping'i düzelttikten sonra:
- Order'dan Contract oluşturma çalışacak
- Contract.Description alanında "10 Computer Quote" göreceksiniz
- Artık hata almayacaksınız!

## 🆘 Son Çare

Hala çalışmazsa, şunları deneyin:
1. Sayfayı yenileyin (F5)
2. Farklı bir browser kullanın
3. Org'dan çıkıp tekrar girin
4. Bu path'i deneyin: `/lightning/setup/ContextUseCaseMappings/home`