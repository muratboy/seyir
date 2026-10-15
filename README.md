# Takip

Günlük aktivitelerini, alışkanlıklarını ve hedeflerini takip eden, çevrimdışı çalışan bir Android uygulaması. Veriler yalnızca cihazdaki SQLite veritabanında tutulur; internet yalnızca bir bağlantıdan yol haritası eklerken, o bağlantıyı indirmek için kullanılır.

## Neler yapar

- **Günlük:** "30 dk koşu", "2 bardak su" gibi serbest metinle kayıt (yazarken ne olacağını gösteren önizlemeyle), sesle giriş, kronometre / geri sayım / pomodoro, günün akışı, uyku ve adım takibi.
- **Hedefler:** günlük, haftalık, aylık ve toplam hedefler ile limitler, alışkanlıklar için seri ve ısı haritası, yol haritaları (yapay zekâ kalıbıyla, elle ya da paylaşılan bir https bağlantısından eklenir). Yol haritası adımları bir aktiviteye bağlanabilir: aktivitenin kayıtları adımı ilerletir, hedefe ulaşılınca adım kendiliğinden tamamlanır.
- **İstatistik:** gün / hafta / ay / yıl görünümleri, önceki dönemle karşılaştırma, kategori dağılımı.
- **Ayarlar:** tema ve dil (Türkçe / İngilizce), aktivite ve ölçü yönetimi, bildirimler ve hatırlatıcılar, ana ekran widget'ı, JSON yedek (günlük otomatik yerel yedek dahil), PDF ve CSV dışa aktarma.

## Çalıştırma ve test

```sh
flutter pub get
flutter run                    # bağlı cihaz ya da emülatör
flutter analyze
flutter test                   # gerçek SQLite ile çalışır; sistemde libsqlite3 kurulu olmalı
flutter build apk --release
```

Release derlemesi henüz bir release anahtarı tanımlanmadığı için debug anahtarıyla imzalanır (`android/app/build.gradle.kts`): telefona kurulur ama mağazaya yüklenemez.

## Klasörler

| Klasör | İçerik |
| --- | --- |
| `lib/data` | Veritabanı (`db.dart`), modeller, uygulama durumu ve iş mantığı (`store.dart`) |
| `lib/logic` | Biçimlendirme, yerelleştirme, metin eşleştirme, dönem istatistikleri |
| `lib/services` | Bildirimler, yedek, dışa aktarma, sesli giriş, adım sensörü, metin ve yol haritası çözümleyicileri |
| `lib/ui` | Sayfalar ve bileşenler |
| `android` | Android projesi: ana ekran widget'ı, bildirim simgeleri, R8 kuralları |
| `test` | Birim ve widget testleri (gerçek SQLite altyapısı: `test/support/real_db.dart`) |
