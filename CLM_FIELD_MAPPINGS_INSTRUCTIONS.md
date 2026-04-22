# CLM Field Mappings - ASIL SORUN BURADA!

## 🚨 ÖNEMLİ KEŞİF

Hata mesajı hala "Name field" diyor. Bu demek ki **iki farklı mapping yeri var**:
1. ✅ Context Use Case Mappings (düzelttik)
2. ❌ **Field Mappings** (BURADA SORUN VAR!)

## 📍 Tarayıcınızda Açılan Sayfa

Şu anda **Setup > CLM > Field Mappings** sayfası açık.

## 🔍 YAPMANIZ GEREKENLER

### ADIM 1: Order-to-Contract Mapping Bulun

Field Mappings sayfasında şunlardan birini arayın:
- "Order to Contract"
- "Order → Contract"
- "Source: Order, Target: Contract"

### ADIM 2: Mapping'i Açın ve Düzenleyin

1. Bu mapping'e tıklayın (Edit veya View Details)
2. Field-to-Field mapping listesini göreceksiniz

### ADIM 3: Name Field Mapping'ini Bulun

Listede şöyle bir satır arayın:
```
Source Field: Name (Order.Name)
Target Field: Name (Contract.Name) ❌ SORUN BURADA!
```

### ADIM 4: İKİ SEÇENEK

**SEÇENEK A: Mapping'i SİLİN (ÖNERİLEN)**
1. Name field mapping satırını bulun
2. Delete/Remove butonuna tıklayın
3. Save

**SEÇENEK B: Target Field'ı DEĞİŞTİRİN**
1. Name field mapping satırını bulun
2. Edit/Modify tıklayın
3. **Target Field** değiştirin:
   - Eski: `Name` ❌
   - Yeni: `Description` ✅ veya `CustomerSignedTitle` ✅
4. Save

## 📸 Göreceğiniz Ekran

Field Mappings sayfasında şöyle bir tablo olmalı:

| Source Object | Source Field | Target Object | Target Field | Actions |
|--------------|--------------|---------------|--------------|---------|
| Order        | Name         | Contract      | Name ❌      | Edit/Delete |
| Order        | AccountId    | Contract      | AccountId    | Edit/Delete |
| Order        | ...          | Contract      | ...          | Edit/Delete |

## ⚠️ DİKKAT

- **Name → Name** mapping'ini mutlaka düzeltin veya silin
- Contract objesinde Name field'ı YOK
- Bu yüzden hata alıyorsunuz

## ✅ Düzeltme Sonrası

Mapping'i düzelttikten sonra:
1. Order sayfasına gidin
2. "Create Contract" tıklayın
3. ✅ Artık çalışacak!

## 🆘 Mapping Bulamazsanız

Eğer Field Mappings sayfası boşsa veya Order-to-Contract mapping yoksa:
1. Screenshot alın ve paylaşın
2. "New Field Mapping" butonuna tıklayın
3. Manuel olarak oluşturalım

## 📝 Field Mapping Şablonu (Yeni Oluşturacaksanız)

```
Source Object: Order
Target Object: Contract

Field Mappings:
- AccountId → AccountId (required)
- Name → Description veya CustomerSignedTitle
- EffectiveDate → StartDate
- Status → Status
```

## 🎯 Özet

**SORUN**: Field Mappings'de Order.Name → Contract.Name (geçersiz)
**ÇÖZÜM**: Bu mapping'i silin VEYA Contract.Description/CustomerSignedTitle ile değiştirina