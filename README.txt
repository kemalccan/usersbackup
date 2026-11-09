usersbackup v3.0 - Windows 10/11 - KURULUM VE KULLANIM
====================================================

Paketin icerigi:
  usersbackup.ps1    : Tek dosyalik, WinForms arayuzlu v3 uygulamasi.
  usersbackup.ico    : Uygulama ve EXE simgesi (kaynak dosya; EXE'ye gomulur).
  EXE_OLUSTUR.cmd    : Windows'ta tek EXE yapmak icin yardimci dosya.

Tek EXE olusturmak:
  1. Windows PowerShell 5.1'de ps2exe modulu kurulu olmali.
     Gerekirse: Install-Module ps2exe -Scope CurrentUser -Force
  2. EXE_OLUSTUR.cmd dosyasini cift tiklayin.
  3. Olusan usersbackup.exe dosyasini harici SSD'ye atin.
  4. Diger bilgisayarlarda yalnizca usersbackup.exe dosyasini acin.
     PS2EXE modulu DIGER bilgisayarlara kurulmaz.

.ps1 olarak calistirmak:
  Windows PowerShell 5.1 ile acin. Windows Forms Windows ortaminda gerekir.
  Kurum guvenlik politikalari script/EXE calistirmayi sinirlayabilir.

Temel yapisi:
  D:\backup\<aktif Windows kullanici adi>\Desktop
  D:\backup\<aktif Windows kullanici adi>\Downloads
  D:\backup\<aktif Windows kullanici adi>\Documents
  D:\backup\<aktif Windows kullanici adi>\CustomFolders
  D:\backup\<aktif Windows kullanici adi>\BrowserBookmarks
  D:\backup\<aktif Windows kullanici adi>\Outlook
  D:\backup\<aktif Windows kullanici adi>\ProgramInventory
  D:\backup\<aktif Windows kullanici adi>\Drivers
  D:\backup\<aktif Windows kullanici adi>\backup_manifest.json
  D:\backup\<aktif Windows kullanici adi>\usersbackup_Backup_rapor_*.txt

Notlar ve sinirlar:
  - Calisan Windows hesabinin verilere erisimi esas alinir.
  - Hedef disk varsayilan olarak EXE'nin bulundugu disktir.
  - Kaynak dosyalar silinmez; kopyalanan dosyalar SHA-256 ile dogrulanir.
  - Degismedigi dusunulen dosyalar boyut ve tarih ile atlanir (hash tekrar edilmez).
  - Tarihli eski surumleri saklayan tam surumleme sistemi YOKTUR.
  - V2'den kalan, manifesti olmayan D:\backup\kullanici klasorune yazilmaz;
    eski klasoru korumak icin elle farkli adla arsivlemek gerekir.
  - Ayni isimli fakat farkli SID/domain hesabiyle mevcut yedek uzerine yazilmaz.
  - Chrome/Edge favorileri Bookmarks dosyalari, Firefox bookmarkbackups .jsonlz4
    dosyalari olarak tasinir. Sifreler, cookie'ler, oturum jetonlari alinmaz.
  - Varsayilan tarayici geri yuklemesi belgeler altinda BrowserImport klasorudur;
    Chrome/Edge profiline dogrudan uygulama AYRI onayla etkindir.
    Firefox .jsonlz4 dosyalarini Firefox'un Library/Import and Backup/Restore
    arayuzunden iceri aktarabilirsiniz; mevcut yer imleri degisebilir.
  - Outlook'ta yalnizca yaygin konumlardaki PST dosyalari bulunur;
    OST dosyalari ve bulut posta hesabi ayarlari tasinmaz.
    Outlook kapaliyken PST yedeklemek daha guvenlidir.
    Geri yuklenen PST yeni PC'de Outlook icinde ayrica acilabilir.
  - Program envanteri uygulamalari YENIDEN KURMAZ; CSV listeler.
  - INF modu tum ucuncu taraf INF paketlerini diskten disari aktarabilir;
    gercekten yeni bilgisayara uygunluk donanim/surumune baglidir.
    INF aktarimi secilirse Windows yonetici onayi istenebilir; acilista istenmez.
    Geri yuklemede suruculer Documents altinda ayri klasore alinip otomatik KURULMAZ.
  - Giris yapilmis Windows kullanicisinin Desktop/Downloads gibi yonlendirilmis
    klasorleri Windows API/ilgili registry uzerinden cozumlenecektir.
  - OneDrive yalnizca bulutta olan dosyalar veya kullanimda olan dosyalar
    guvenle kopyalanamayabilir; TXT raporundaki uyariyi kontrol edin.
  - Yedekler sifreli DEGILDIR. SSD'yi guvenli yerde saklayin.
  - Islem Windows ortaminda fiilen test edilmemistir. Once test dosyalari ile
    yedekleme ve geri yukleme denenmelidir.

Guvenlik: Otomatik admin olarak calisma / UAC'yi gecme yoktur.
TXT raporlar yedeklenen kullanici veya geri yukleyen kullanicinin Belgeler klasorundedir.
TXT rapor aciklama amaclidir; manifest JSON ise programca okunur.
