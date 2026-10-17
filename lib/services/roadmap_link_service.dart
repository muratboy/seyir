import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bağlantıdan yol haritası indirirken ne ters gidebileceği; arayüz her biri için ayrı bir açıklama yazar.
enum RoadmapLinkProblem {
  /// Yazılan şey bir internet adresine benzemiyor.
  invalidLink,

  /// https olmayan adres.
  insecure,

  /// Yalnızca kullanıcının kendi cihazında ya da ağında geçerli bir adres.
  localAddress,

  /// Sunucuya ulaşılamadı (internet yok, adres yok, sertifika geçersiz).
  network,

  /// Sunucu zamanında yanıt vermedi.
  timeout,

  /// Sunucu 200 dışında bir durum döndü; [RoadmapLinkException.status] içinde.
  status,

  /// Beklenenden büyük bir dosya.
  tooLarge,

  /// Bağlantı çok fazla yönlendiriyor.
  tooManyRedirects,
}

class RoadmapLinkException implements Exception {
  final RoadmapLinkProblem problem;
  final int? status;

  const RoadmapLinkException(this.problem, {this.status});

  @override
  String toString() => 'RoadmapLinkException($problem${status == null ? '' : ', $status'})';
}

typedef RoadmapLinkFetcher = Future<String> Function(Uri uri);

/// Paylaşılan bir yol haritasını internet bağlantısından okur.
///
/// Uygulama çevrimdışı çalışır; ağa yalnızca kullanıcı bir bağlantı yapıştırıp "Getir"e bastığında çıkılır.
/// Bu yüzden istek temkinli yapılır: yalnızca https, yerel adreslere yok, küçük bir boyut sınırı, kısa zaman
/// aşımı ve yönlendirmelerin her adımında aynı denetim. İndirilen şey yalnızca metin olarak okunur.
class RoadmapLinkService {
  RoadmapLinkService._();

  /// Bir yol haritası metni bundan çok küçüktür; büyük dosya yanlış bir adrese işaret ediyordur.
  static const maxBytes = 256 * 1024;

  /// Bir yol haritasında kabul edilen en çok adım (yapay zekâ kalıbı onlarcasını üretir).
  static const maxSteps = 200;

  static const maxRedirects = 5;

  /// Yapıştırılan metni indirilecek adrese çevirir; bu bir https adresi değilse [RoadmapLinkException] atar.
  ///
  /// Mesajdan kopyalanmış metin ("Bak: https://… harika") ve şemasız adres ("github.com/…") de kabul edilir.
  /// GitHub dosya ve gist sayfaları ile Pastebin sayfaları, asıl metni veren "ham" adreslerine çevrilir; çünkü
  /// kullanıcılar adres çubuğundaki sayfayı paylaşır, sayfa ise HTML'dir.
  ///
  /// [allowInsecure] yalnızca testler içindir: https ve yerel adres denetimini kapatır.
  static Uri normalize(String input, {bool allowInsecure = false}) {
    const invalid = RoadmapLinkException(RoadmapLinkProblem.invalidLink);
    final tokens = input.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    var token = tokens.where((t) => t.contains('://')).firstOrNull ??
        tokens.where((t) => t.contains('.')).firstOrNull;
    if (token == null) throw invalid;

    // Mesajlardaki sarmalayıcı ve cümle sonu işaretleri.
    token = token.replaceAll(RegExp(r'''^[<("']+|[>)"'.,;:!?\]]+$'''), '');
    if (!token.contains('://')) {
      // "javascript:…" gibi şemalar burada elenir: alan adı biçimine uymazlar.
      if (!RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?([/?#]|$)').hasMatch(token)) throw invalid;
      token = 'https://$token';
    }

    final uri = Uri.tryParse(token);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) throw invalid;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') throw invalid;
    check(uri, allowInsecure: allowInsecure);
    return _rawLink(uri);
  }

  /// [uri] indirilebilir mi: https ve internette bir adres olmalı. İlk adreste olduğu gibi her yönlendirmede
  /// de çağrılır; yoksa herkese açık bir sayfa, kullanıcıyı kendi ağındaki bir adrese yönlendirebilirdi.
  static void check(Uri uri, {bool allowInsecure = false}) {
    if (allowInsecure) return;
    if (uri.scheme.toLowerCase() != 'https') throw const RoadmapLinkException(RoadmapLinkProblem.insecure);
    if (_isLocalHost(uri.host)) throw const RoadmapLinkException(RoadmapLinkProblem.localAddress);
  }

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal')) return true;
    if (!h.contains('.') && !h.contains(':')) return true; // tek etiketli ağ adı ("router", "nas")
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 0 ||
          b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    // IPv6: benzersiz yerel adresler (fc00::/7), belirsiz adres ve IPv4'e eşlenmiş adresler.
    return (b[0] & 0xfe) == 0xfc || b.every((x) => x == 0) || (b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xff);
  }

  /// Sayfa adreslerini ham metin adreslerine çevirir; tanınmayan adres olduğu gibi kalır.
  static Uri _rawLink(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (host == 'github.com' && parts.length >= 5 && parts[2] == 'blob') {
      return Uri.https('raw.githubusercontent.com', '/${parts[0]}/${parts[1]}/${parts[3]}/${parts.sublist(4).join('/')}');
    }
    if (host == 'gist.github.com' && parts.length >= 2) {
      return Uri.https('gist.githubusercontent.com', '/${parts[0]}/${parts[1]}/raw');
    }
    if (host == 'pastebin.com' && parts.length == 1 && parts[0] != 'raw') {
      return Uri.https('pastebin.com', '/raw/${parts[0]}');
    }
    return uri;
  }

  /// [uri] adresindeki metni indirir. Hatalar [RoadmapLinkException] olarak atılır.
  static Future<String> fetch(
    Uri uri, {
    bool allowInsecure = false,
    Duration timeout = const Duration(seconds: 15),
    int maxBytes = RoadmapLinkService.maxBytes,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Seyir';
    try {
      return await _download(client, uri, allowInsecure, timeout, maxBytes).timeout(timeout * 2);
    } on RoadmapLinkException {
      rethrow;
    } on TimeoutException {
      throw const RoadmapLinkException(RoadmapLinkProblem.timeout);
    } on IOException {
      throw const RoadmapLinkException(RoadmapLinkProblem.network);
    } on FormatException {
      // Sunucunun gönderdiği bozuk bir yönlendirme adresi.
      throw const RoadmapLinkException(RoadmapLinkProblem.network);
    } finally {
      // Zaman aşımında hâlâ süren istek de böylece kesilir.
      client.close(force: true);
    }
  }

  static Future<String> _download(HttpClient client, Uri first, bool allowInsecure, Duration timeout, int maxBytes) async {
    var uri = first;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      check(uri, allowInsecure: allowInsecure);
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false; // yönlendirmeleri kendimiz izleriz: her adım denetlenmeli
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain;q=0.9, text/markdown;q=0.8, */*;q=0.1');
      final response = await request.close().timeout(timeout);
      final status = response.statusCode;

      if (status >= 300 && status < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw RoadmapLinkException(RoadmapLinkProblem.status, status: status);
        uri = uri.resolve(location);
        continue;
      }
      if (status != HttpStatus.ok) throw RoadmapLinkException(RoadmapLinkProblem.status, status: status);
      if (response.contentLength > maxBytes) throw const RoadmapLinkException(RoadmapLinkProblem.tooLarge);

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw const RoadmapLinkException(RoadmapLinkProblem.tooLarge);
      }
      final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      return text.startsWith('﻿') ? text.substring(1) : text;
    }
    throw const RoadmapLinkException(RoadmapLinkProblem.tooManyRedirects);
  }
}
