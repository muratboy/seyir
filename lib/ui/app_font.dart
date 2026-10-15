/// Uygulamanın yazı boyutu ölçeği. Boyutlar tek tek sayı olarak yazılmaz; bu basamaklardan biri seçilir.
/// En küçük basamak 11'dir: daha küçük yazılar telefonda okunaklı olmuyordu.
abstract final class AppFont {
  /// Rozetler, ısı haritası etiketleri, en küçük yardımcı yazılar.
  static const double micro = 11;

  /// İkincil bilgi: alt yazılar, ipuçları, çip etiketleri.
  static const double caption = 12;

  /// Yoğun listelerdeki gövde metni.
  static const double small = 13;

  /// Varsayılan gövde metni.
  static const double body = 14;

  /// Kart ve liste öğesi başlıkları.
  static const double subtitle = 16;

  /// Bölüm ve pencere başlıkları.
  static const double title = 18;

  /// Öne çıkan değerler.
  static const double headline = 20;

  /// Büyük sayılar, büyük simgeler.
  static const double display = 24;

  /// Sayaç süresi gibi tek başına duran en büyük yazılar.
  static const double hero = 32;
}
