<div align="center">

# 🗂️ usersbackup

### Windows kullanıcı yedekleme ve geri yükleme aracı

**Taşınabilir · Sade arayüz · Kullanıcı odaklı · PowerShell / Windows Forms**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Sürüm](https://img.shields.io/badge/Sürüm-v3.0.2-617EB5)
![Geliştirme](https://img.shields.io/badge/v4-Yol%20Haritasında-orange)

**Kullanıcı dosyalarınızı, tarayıcı favorilerinizi ve seçili Windows verilerini harici bir diske yedekleyin; gerektiğinde başka bir bilgisayarda geri yükleyin.**

</div>

---

## 📌 usersbackup nedir?

**usersbackup**, Windows 10/11 bilgisayarlarda oturum açmış kullanıcının erişebildiği verileri seçilen diske kopyalamak ve daha sonra geri yüklemek için geliştirilmiş grafik arayüzlü bir araçtır.

Özellikle **bilgisayar değişimi**, **harici SSD'ye kullanıcı yedeği alma** ve **domain ortamlarında kullanıcı bazlı veri taşıma** senaryoları için tasarlanmıştır.

- Açık renkli, sade ve **yeniden boyutlandırılabilir** pencere
- **Yedekleme** ve **Geri Yükleme** sekmeleri
- İstenilen hedef disk ve kullanıcı klasörlerini seçebilme
- Programın çalıştığı diski varsayılan hedef olarak önerebilme
- İşlem ilerlemesi, durdurma ve TXT raporu
- Normal açılışta **yönetici yetkisi istememe**

> [!IMPORTANT]
> usersbackup **tam sistem imajı**, kurulu programları taşıyan bir klonlama aracı veya kurumsal yedekleme altyapısının yerine geçen bir çözüm değildir. Mevcut v3'ün gerçek yedekleme ve geri yükleme akışlarını kendi ortamınızda küçük test verileriyle doğrulayın.

## 🖼️ Arayüz

Uygulama iki temel sekmeden oluşur:

| Yedekleme | Geri Yükleme |
|---|---|
| Disk, klasör ve ek veri türlerini seçme | Kaynak yedeği ve geri yüklenecek öğeleri seçme |
| İlerleme çubuğu, durdurma ve işlem raporu | Dosya çakışma seçenekleri ve işlem raporu |

> Ekran görüntüsü eklemek için repo içinde `assets/usersbackup-yedekleme.png` ve `assets/usersbackup-geri-yukleme.png` dosyalarını oluşturup aşağıdaki satırları etkinleştirebilirsiniz.
>
> `![Yedekleme ekranı](assets/usersbackup-yedekleme.png)`  
> `![Geri yükleme ekranı](assets/usersbackup-geri-yukleme.png)`

## ✨ v3 özellikleri

| Modül | Ne yapar? |
|---|---|
| 📁 **Kullanıcı klasörleri** | Masaüstü, İndirilenler, Belgeler, Resimler, Videolar ve Müzik klasörlerini seçerek yedekler. |
| ➕ **Özel klasör ekleme** | Kullanıcının erişebildiği ilave klasörleri seçmesine izin verir. |
| 🌐 **Tarayıcı favorileri** | Chrome/Edge profil `Bookmarks` dosyalarını ve Firefox'un mevcut yer imi yedeklerini toplar. **Şifreler ve oturum bilgileri yedeklenmez.** |
| 📧 **Outlook PST** | Bulabildiği `.pst` arşiv dosyalarını yedekler. Outlook hesaplarını otomatik yapılandırmaz; `.ost` önbellekleri varsayılan hedef değildir. |
| 💻 **Program envanteri** | Windows kayıtlarından tespit edilen kurulu programların listesini `InstalledPrograms.csv` olarak dışa aktarır; programları taşımaz/kurmaz. |
| 🧩 **INF sürücü paketleri** | Seçildiğinde Windows `pnputil` ile üçüncü taraf sürücü paketlerini dışa aktarmayı dener. **Ayrı UAC onayı gerekir.** |
| ♻️ **Geri yükleme** | Seçilen verileri oturumdaki kullanıcının uygun klasörlerine aktarır; çakışmalarda atla / yeniden adlandır / üzerine yaz seçenekleri sunar. |

### Geri yüklemede özel davranışlar

- **Standart klasörler:** Yeni bilgisayardaki mevcut Windows kullanıcısının karşılık gelen klasörlerine aktarılır.
- **Özel klasörler:** Belgeler altında `usersbackup_Restored` dizinine çıkarılır.
- **Chrome / Edge:** Varsayılan olarak `Documents\usersbackup_BrowserImport` altına hazırlanır. Kullanıcı ayrıca izin verirse ve tarayıcı kapalıysa mevcut profil dosyalarına uygulanabilir.
- **Firefox:** Yer imi yedekleri içe aktarılmak üzere hazırlanır; otomatik profil kurulumu yapılmaz.
- **Outlook:** PST dosyaları `Documents\Outlook Files\usersbackup_Imported` altına kopyalanır.
- **INF paketleri:** `Documents\usersbackup_RestoredDrivers` altına çıkarılır; sürücüler **otomatik yüklenmez**.
- **Program envanteri:** Bilgilendirme amacıyla saklanır; otomatik uygulama kurulumu yapılmaz.

## 📂 Yedekleme klasör yapısı

Örneğin hedef disk `D:` ve oturumdaki Windows kullanıcı adı `ahmet` ise:

```text
D:\
└── BACKUP\
    └── ahmet\
        ├── Desktop\
        ├── Downloads\
        ├── Documents\
        ├── Pictures\
        ├── Music\
        ├── Videos\
        ├── CustomFolders\
        ├── BrowserBookmarks\
        ├── Outlook\
        ├── Drivers\
        ├── ProgramInventory\
        │   └── InstalledPrograms.csv
        ├── backup_manifest.json
        └── usersbackup_Backup_rapor_YYYYMMDD_HHMMSS.txt
```

*Yalnızca seçilen ve içeriği bulunan modüllerin klasörleri oluşabilir.*

**Klasör yolu:** `HEDEF_DISK:\BACKUP\KULLANICI_ADI\`  
Bilgisayar adı veya araya eklenmiş `users` klasörü kullanılmaz.

Domain hesaplarında uygulama çalıştırıldığı Windows kimliğini algılar. Aynı ada sahip farklı hesapların yedeklerini karıştırmamak için manifestte hesap ve SID bilgileri kontrol edilir. **Kaynak kullanıcının adı, yeni bilgisayardaki hedef kullanıcı adıyla aynı olmak zorunda değildir.**

## 🚀 Kurulum ve kullanım

### Gereksinimler

- Windows 10 veya Windows 11
- **Windows PowerShell 5.1**
- .NET Framework 4.7+ (Windows Forms için)
- Yedek dosyalarını kaydetmek için yazma izni olan hedef disk (harici SSD önerilir)

### Seçenek A — PowerShell dosyasını çalıştırma

Depoyu indirin ve **Windows PowerShell** içinde ilgili klasöre geçin:

```powershell
cd "C:\usersbackup"
.\usersbackup.ps1
```

`.ps1` dosyasının çalışması, Windows'un **execution policy** ve dijital imza kurallarına bağlıdır. Kurum bilgisayarlarında BT politikalarını aşmayın; gerekiyorsa BT ekibinden onay alın.

### Seçenek B — Tek EXE oluşturma (PS2EXE)

Derleme yapacağınız Windows bilgisayarda:

```powershell
Install-Module ps2exe -Scope CurrentUser

Invoke-ps2exe `
  -inputFile ".\usersbackup.ps1" `
  -outputFile ".\usersbackup.exe" `
  -noConsole -STA -DPIAware `
  -title "usersbackup"
```

Oluşan `usersbackup.exe` dosyasını harici SSD'ye kopyalayarak kullanabilirsiniz. EXE tek dosyadır; ancak Windows PowerShell / .NET altyapısına dayanır ve kurumunuzun güvenlik politikalarına tabi olmaya devam eder.

> [!NOTE]
> Normal program açılışı UAC istemez. **INF sürücü paketi dışa aktarma** seçeneği etkinleştirilirse ayrı bir yönetici onayı penceresi açılabilir.

### Yedekleme adımları

1. Harici SSD'yi takın ve **usersbackup** uygulamasını açın.
2. **Hedef disk** alanından doğru diski seçin.
3. Standart klasörleri işaretleyin; gerekirse **+ Klasör ekle** ile özel klasör ekleyin.
4. İhtiyaç duyduğunuz tarayıcı, Outlook, program listesi veya INF modüllerini seçin.
5. **Yedeklemeyi Başlat** butonuna basın.
6. Bittiğinde **Son TXT Raporu** üzerinden sonuçları ve uyarıları kontrol edin.

### Geri yükleme adımları

1. **Geri Yükleme** sekmesine geçin.
2. SSD'den `BACKUP\kullanıcı_adı` klasörünü seçin.
3. Geri yüklenecek veri türlerini işaretleyin.
4. Dosya çakışmaları için **Atla (önerilen)**, **Yeniden adlandır** veya **Üzerine yaz** politikasını seçin.
5. **Geri Yüklemeyi Başlat** ile aktarımı gerçekleştirin.
6. TXT raporunu kontrol edin; tarayıcı/Outlook verilerinin içe aktarımı için gerektiğinde uygulamaların kendi işlemlerini tamamlayın.

> [!WARNING]
> **Üzerine yaz** seçeneği hedefteki mevcut dosyaları değiştirebilir. İlk kullanımda **Atla** seçeneğini ve küçük bir test klasörünü tercih edin.

## 🔐 Güvenlik ve sınırlamalar

- **Kaynak dosyalar silinmez.** Bu araç kopyalama/geri yükleme için tasarlanmıştır.
- Uygulama **aktif oturumun izinleriyle** çalışır; diğer kullanıcı profillerinin korumalı dosyalarına erişim sağlamaz.
- Sürücü paketleri yetki gerektirir; farklı bilgisayara aktarılmaları sürücülerin o donanımda çalışacağını garanti etmez.
- Kullanımda olan veya erişilemeyen PST / diğer dosyalar atlanabilir ya da hata oluşturabilir; raporu mutlaka inceleyin.
- Dosya kopyalama sırasında SHA-256 karşılaştırması uygulanır; ancak v3'te **tüm mevcut yedeği bağımsız olarak tarayan sağlık kontrolü bulunmaz**.
- Yedekler **şifrelenmez**. Harici SSD'yi koruyun; hassas kurum verileri için kuruluşun onayladığı disk şifrelemesi ve saklama kurallarını kullanın.
- Tek EXE üretmek, kod imzalama veya Windows/kurum uygulama güvenlik kontrollerini ortadan kaldırmaz.
- Windows kullanıcı profili, kurulu yazılımlar ve sistem ayarlarının tamamı yeni bilgisayara taşınmaz.

## 🛣️ v4 yol haritası

**Aşağıdakiler planlanan geliştirmelerdir; mevcut v3 sürümünde tamamlanmış özellikler olarak değerlendirilmemelidir.**

- [ ] Akıllı, artımlı yedekleme motorunu güçlendirme
- [ ] Manifest üzerinden **yedek sağlık kontrolü** ve kapsamlı SHA-256 doğrulama
- [ ] Geri yükleme öncesi **dosya ve çakışma önizlemesi**
- [ ] Kesilen yedeklemeyi güvenli biçimde **kaldığı yerden sürdürme**
- [ ] Aktarım hızı (MB/sn), işlenen veri ve tahmini kalan süre
- [ ] Bilgisayar değişim asistanı ve adım adım veri taşıma
- [ ] Daha ayrıntılı TXT raporu, başarısız dosyaları tekrar deneme
- [ ] İsteğe bağlı önceki dosya sürümlerini saklama
- [ ] Gelişmiş dosya ve klasör hariç tutma filtreleri

**v4'te de korunacak prensipler:** tek EXE, açık ve sade tasarım, yeniden boyutlandırılabilir arayüz, `BACKUP\kullanıcı_adı` dizin düzeni, domain kullanıcı desteği ve normal açılışta UAC gerektirmeme.

## 🤝 Katkıda bulunma

Hata raporları ve geliştirme önerileri için GitHub **Issues** bölümünü kullanabilirsiniz. Değişiklik önerilerini **Pull Request** olarak paylaşabilirsiniz.

Hata bildirirken Windows sürümünü, uygulama sürümünü, hatanın hangi işlemde çıktığını ve **kişisel bilgi içermeyen** ilgili rapor satırlarını ekleyin. Domain adlarını, kullanıcı dosyası içeriklerini, erişim tokenlarını ve özel yolları paylaşmadan önce maskeleyin.

## 📄 Lisans

Bu depo için henüz bir lisans seçilmediyse kaynak kod **otomatik olarak açık kaynak lisanslı sayılmaz**. Paylaşım ve yeniden kullanım koşullarını belirlemek için depoya ayrıca bir `LICENSE` dosyası ekleyin.

---

<div align="center">

**usersbackup** — *Önemli dosyalarınızı kontrollü biçimde yedekleyin, ihtiyaç duyduğunuzda geri yükleyin.*

</div>
