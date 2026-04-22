# Salesforce Setup'tan Context Use Case Mappings'e Manuel Gitme

## 🎯 ADIM ADIM TALİMATLAR

### ADIM 1: Setup'ı Açın
1. Salesforce'ta sağ üst köşedeki **⚙️ (dişli çark)** ikonuna tıklayın
2. **Setup** seçeneğine tıklayın
3. Setup ana sayfası açılacak

### ADIM 2: Quick Find (Hızlı Arama) Kullanın
1. Sol taraftaki menüde **"Quick Find"** arama kutusunu göreceksiniz
2. Bu kutuya şunu yazın: `context`
3. Yazarken alt kısımda sonuçlar görünmeye başlayacak

### ADIM 3: Arama Sonuçlarında Bulun
Arama sonuçlarında şunlardan birini arayın:
- **"Context Use Case Mappings"**
- **"Context Definitions"**
- **"Context Mappings"**
- **"Contract Lifecycle Management"** altında bir şeyler

### ADIM 4A: Eğer "Context Use Case Mappings" Varsa
1. **Context Use Case Mappings** üzerine tıklayın
2. Açılan sayfada mapping'leri göreceksiniz
3. Order → Contract mapping'ini bulun

### ADIM 4B: Eğer "Context Use Case Mappings" Yoksa - CLM Deneyin
1. Quick Find'da şunu arayın: `clm`
2. Veya: `contract lifecycle`
3. Şu seçenekleri arayın:
   - **Contract Lifecycle Management**
   - **CLM Settings**
   - **CLM Configuration**

### ADIM 5: Alternatif - Object Manager Üzerinden
Eğer yukarıdakiler yoksa:

1. Quick Find'da: `object manager` yazın
2. **Object Manager** tıklayın
3. Object listesinde **Order** bulun ve tıklayın
4. Sol menüde şunlara bakın:
   - **Buttons, Links, and Actions** 
   - **Page Layouts**
5. "Create Contract" adında bir action var mı kontrol edin

### ADIM 6: Başka Alternatif - Process Builder/Flow
1. Quick Find'da: `flows` yazın
2. **Flows** sayfasını açın
3. "Order" veya "Contract" kelimelerini içeren flow'ları arayın
4. Varsa açın ve Name field mapping'ini kontrol edin

## 📸 Screenshot Paylaşın

Eğer hiçbirini bulamıyorsanız, şunları yapın:

### Screenshot 1: Quick Find Sonuçları
1. Quick Find'da `context` yazın
2. Çıkan sonuçların screenshot'ını alın

### Screenshot 2: Quick Find CLM
1. Quick Find'da `clm` yazın
2. Çıkan sonuçların screenshot'ını alın

### Screenshot 3: Quick Find Contract
1. Quick Find'da `contract` yazın
2. Çıkan sonuçların screenshot'ını alın

## 🎯 Neyi Arıyoruz?

Şu bilgileri içeren bir sayfa arıyoruz:
- **Reference Object**: Order
- **Target Object**: Contract
- **Target Object Custom Field Name**: (burası düzeltilecek)

## ⚠️ Permission Sorunu Olabilir

"Page not found" hatası izin sorununa işaret edebilir:
1. System Administrator profili gerekebilir
2. CLM lisansı aktif olmalı
3. Contract Lifecycle Management permission set'i atanmış olmalı

## 🔧 Geçici Çözüm - Direct URL

Tarayıcıda bu URL'leri deneyin (Salesforce instance'ınıza göre):

```
[YOUR-INSTANCE].salesforce.com/lightning/setup/ContextUseCaseMappings/home
```

Örnek:
```
your-org.develop.my.salesforce.com/lightning/setup/ContextUseCaseMappings/home
```

## 📞 Yardım

Screenshot'ları paylaşın, beraber bulalım:
1. Quick Find'da "context" arama sonuçları
2. Quick Find'da "clm" arama sonuçları
3. Soldaki Setup menüsünün görünen kısmı