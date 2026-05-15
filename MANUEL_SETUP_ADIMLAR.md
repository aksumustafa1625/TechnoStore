# Salesforce Setup'tan Context Use Case Mappings'e Manuel Gitme

## ðŸŽ¯ ADIM ADIM TALÄ°MATLAR

### ADIM 1: Setup'Ä± AÃ§Ä±n
1. Salesforce'ta saÄŸ Ã¼st kÃ¶ÅŸedeki **âš™ï¸ (diÅŸli Ã§ark)** ikonuna tÄ±klayÄ±n
2. **Setup** seÃ§eneÄŸine tÄ±klayÄ±n
3. Setup ana sayfasÄ± aÃ§Ä±lacak

### ADIM 2: Quick Find (HÄ±zlÄ± Arama) KullanÄ±n
1. Sol taraftaki menÃ¼de **"Quick Find"** arama kutusunu gÃ¶receksiniz
2. Bu kutuya ÅŸunu yazÄ±n: `context`
3. Yazarken alt kÄ±sÄ±mda sonuÃ§lar gÃ¶rÃ¼nmeye baÅŸlayacak

### ADIM 3: Arama SonuÃ§larÄ±nda Bulun
Arama sonuÃ§larÄ±nda ÅŸunlardan birini arayÄ±n:
- **"Context Use Case Mappings"**
- **"Context Definitions"**
- **"Context Mappings"**
- **"Contract Lifecycle Management"** altÄ±nda bir ÅŸeyler

### ADIM 4A: EÄŸer "Context Use Case Mappings" Varsa
1. **Context Use Case Mappings** Ã¼zerine tÄ±klayÄ±n
2. AÃ§Ä±lan sayfada mapping'leri gÃ¶receksiniz
3. Order â†’ Contract mapping'ini bulun

### ADIM 4B: EÄŸer "Context Use Case Mappings" Yoksa - CLM Deneyin
1. Quick Find'da ÅŸunu arayÄ±n: `clm`
2. Veya: `contract lifecycle`
3. Åžu seÃ§enekleri arayÄ±n:
   - **Contract Lifecycle Management**
   - **CLM Settings**
   - **CLM Configuration**

### ADIM 5: Alternatif - Object Manager Ãœzerinden
EÄŸer yukarÄ±dakiler yoksa:

1. Quick Find'da: `object manager` yazÄ±n
2. **Object Manager** tÄ±klayÄ±n
3. Object listesinde **Order** bulun ve tÄ±klayÄ±n
4. Sol menÃ¼de ÅŸunlara bakÄ±n:
   - **Buttons, Links, and Actions** 
   - **Page Layouts**
5. "Create Contract" adÄ±nda bir action var mÄ± kontrol edin

### ADIM 6: BaÅŸka Alternatif - Process Builder/Flow
1. Quick Find'da: `flows` yazÄ±n
2. **Flows** sayfasÄ±nÄ± aÃ§Ä±n
3. "Order" veya "Contract" kelimelerini iÃ§eren flow'larÄ± arayÄ±n
4. Varsa aÃ§Ä±n ve Name field mapping'ini kontrol edin

## ðŸ“¸ Screenshot PaylaÅŸÄ±n

EÄŸer hiÃ§birini bulamÄ±yorsanÄ±z, ÅŸunlarÄ± yapÄ±n:

### Screenshot 1: Quick Find SonuÃ§larÄ±
1. Quick Find'da `context` yazÄ±n
2. Ã‡Ä±kan sonuÃ§larÄ±n screenshot'Ä±nÄ± alÄ±n

### Screenshot 2: Quick Find CLM
1. Quick Find'da `clm` yazÄ±n
2. Ã‡Ä±kan sonuÃ§larÄ±n screenshot'Ä±nÄ± alÄ±n

### Screenshot 3: Quick Find Contract
1. Quick Find'da `contract` yazÄ±n
2. Ã‡Ä±kan sonuÃ§larÄ±n screenshot'Ä±nÄ± alÄ±n

## ðŸŽ¯ Neyi ArÄ±yoruz?

Åžu bilgileri iÃ§eren bir sayfa arÄ±yoruz:
- **Reference Object**: Order
- **Target Object**: Contract
- **Target Object Custom Field Name**: (burasÄ± dÃ¼zeltilecek)

## âš ï¸ Permission Sorunu Olabilir

"Page not found" hatasÄ± izin sorununa iÅŸaret edebilir:
1. System Administrator profili gerekebilir
2. CLM lisansÄ± aktif olmalÄ±
3. Contract Lifecycle Management permission set'i atanmÄ±ÅŸ olmalÄ±

## ðŸ”§ GeÃ§ici Ã‡Ã¶zÃ¼m - Direct URL

TarayÄ±cÄ±da bu URL'leri deneyin (Salesforce instance'Ä±nÄ±za gÃ¶re):

```
[YOUR-INSTANCE].salesforce.com/lightning/setup/ContextUseCaseMappings/home
```

Ã–rnek:
```
your-org.develop.my.salesforce.com/lightning/setup/ContextUseCaseMappings/home
```

## ðŸ“ž YardÄ±m

Screenshot'larÄ± paylaÅŸÄ±n, beraber bulalÄ±m:
1. Quick Find'da "context" arama sonuÃ§larÄ±
2. Quick Find'da "clm" arama sonuÃ§larÄ±
3. Soldaki Setup menÃ¼sÃ¼nÃ¼n gÃ¶rÃ¼nen kÄ±smÄ±