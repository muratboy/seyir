import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takip/services/roadmap_link_service.dart';
import 'package:takip/services/roadmap_parser.dart';

const _shared = '{"title": "Paylaşılan Plan", "emoji": "🔗", "steps": [{"title": "Kaynak seç"}, '
    '{"title": "Kelime çalış", "type": "goal", "target": 300, "unit": "dk"}]}';

Matcher _fails(RoadmapLinkProblem problem) =>
    throwsA(isA<RoadmapLinkException>().having((e) => e.problem, 'problem', problem));

void main() {
  group('A pasted link', () {
    String n(String text) => RoadmapLinkService.normalize(text).toString();

    test('is found in a message, and an address without a scheme gets https', () {
      expect(n('  https://example.com/plan.json  '), 'https://example.com/plan.json');
      expect(n('Şuna bak: https://example.com/plan.json, çok iyi!'), 'https://example.com/plan.json');
      expect(n('<https://example.com/plan.json>'), 'https://example.com/plan.json');
      expect(n('example.com/plan.json'), 'https://example.com/plan.json');
    });

    test('of a GitHub or Pastebin page leads to the raw text', () {
      expect(n('https://github.com/ali/planlar/blob/main/ingilizce/plan.json'),
          'https://raw.githubusercontent.com/ali/planlar/main/ingilizce/plan.json');
      expect(n('https://gist.github.com/ali/0123abcd'), 'https://gist.githubusercontent.com/ali/0123abcd/raw');
      expect(n('https://pastebin.com/AbC123'), 'https://pastebin.com/raw/AbC123');
      expect(n('https://pastebin.com/raw/AbC123'), 'https://pastebin.com/raw/AbC123');
      expect(n('https://raw.githubusercontent.com/ali/planlar/main/plan.json'),
          'https://raw.githubusercontent.com/ali/planlar/main/plan.json');
    });

    test('has to be https and an address on the internet', () {
      for (final text in ['', 'yol haritam', 'javascript:alert(1)', 'file:///sdcard/plan.json',
          'ftp://example.com/plan.json', 'https://ad:sifre@example.com/plan.json']) {
        expect(() => n(text), _fails(RoadmapLinkProblem.invalidLink), reason: text);
      }
      expect(() => n('http://example.com/plan.json'), _fails(RoadmapLinkProblem.insecure));
      for (final text in ['https://localhost/p', 'https://127.0.0.1/p', 'https://192.168.1.1/p', 'https://10.0.0.2/p',
          'https://172.20.1.1/p', 'https://169.254.1.1/p', 'https://[::1]/p', 'https://[fd00::1]/p', 'https://router/p',
          'https://nas.local/p']) {
        expect(() => n(text), _fails(RoadmapLinkProblem.localAddress), reason: text);
      }
      expect(n('https://8.8.8.8/plan.json'), 'https://8.8.8.8/plan.json', reason: 'a public address is fine');
      expect(n('https://172.32.0.1/plan.json'), 'https://172.32.0.1/plan.json', reason: 'outside 172.16/12');
    });

    test('is checked again at every redirect', () {
      expect(() => RoadmapLinkService.check(Uri.parse('http://example.com/x')), _fails(RoadmapLinkProblem.insecure));
      expect(() => RoadmapLinkService.check(Uri.parse('https://192.168.0.1/x')),
          _fails(RoadmapLinkProblem.localAddress));
      RoadmapLinkService.check(Uri.parse('https://example.com/x'));
    });
  });

  group('Fetching a link', () {
    late HttpServer server;
    late Map<String, FutureOr<void> Function(HttpResponse)> routes;

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
    // The test server speaks plain http on the loopback interface, which the app itself never accepts.
    Future<String> get(String path, {Duration timeout = const Duration(seconds: 5)}) =>
        RoadmapLinkService.fetch(at(path), allowInsecure: true, timeout: timeout);

    setUp(() async {
      routes = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final handler = routes[request.uri.path];
        if (handler == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } else {
          await handler(request.response);
        }
      });
    });
    tearDown(() => server.close(force: true));

    test('reads the text, which the roadmap import then understands', () async {
      routes['/plan.json'] = (r) {
        r.headers.contentType = ContentType.json;
        r.write(_shared);
        return r.close();
      };
      final roadmap = RoadmapParser.parse(await get('/plan.json'))!;
      expect(roadmap.title, 'Paylaşılan Plan');
      expect(roadmap.steps.map((s) => s.title), ['Kaynak seç', 'Kelime çalış']);
      expect(roadmap.steps.last.target, 300);
    });

    test('brings back a roadmap someone shared from the app', () async {
      final original = RoadmapParser.parse(_shared)!..title = 'Bir arkadaştan';
      routes['/paylasilan'] = (r) {
        r.write(RoadmapParser.shareText(original, isTr: true));
        return r.close();
      };
      final back = RoadmapParser.parse(await get('/paylasilan'))!;
      expect(back.title, 'Bir arkadaştan');
      expect([for (final s in back.steps) (s.title, s.target, s.unit)],
          [for (final s in original.steps) (s.title, s.target, s.unit)]);
    });

    test('drops a byte order mark and unpacks compressed answers', () async {
      routes['/bom'] = (r) {
        r.add([0xEF, 0xBB, 0xBF, ...utf8.encode(_shared)]);
        return r.close();
      };
      routes['/gzip'] = (r) {
        r.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        r.add(gzip.encode(utf8.encode(_shared)));
        return r.close();
      };
      expect(await get('/bom'), _shared);
      expect(await get('/gzip'), _shared);
    });

    test('follows redirects, but not endlessly', () async {
      routes['/eski'] = (r) => r.redirect(at('/plan.json'));
      routes['/plan.json'] = (r) {
        r.write(_shared);
        return r.close();
      };
      routes['/a'] = (r) => r.redirect(at('/b'));
      routes['/b'] = (r) => r.redirect(at('/a'));
      expect(await get('/eski'), _shared);
      await expectLater(get('/a'), _fails(RoadmapLinkProblem.tooManyRedirects));
    });

    test('reports a missing page with its status', () async {
      await expectLater(
        get('/yok'),
        throwsA(isA<RoadmapLinkException>()
            .having((e) => e.problem, 'problem', RoadmapLinkProblem.status)
            .having((e) => e.status, 'status', 404)),
      );
    });

    test('stops at the size limit, also when the size is not announced or the answer is compressed', () async {
      routes['/buyuk'] = (r) {
        r.headers.contentLength = RoadmapLinkService.maxBytes + 1;
        r.add(List.filled(RoadmapLinkService.maxBytes + 1, 32));
        return r.close();
      };
      routes['/akan'] = (r) async {
        for (var i = 0; i < 40; i++) {
          r.add(List.filled(10 * 1024, 32));
          await r.flush();
        }
        await r.close();
      };
      routes['/bomba'] = (r) {
        r.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        r.add(gzip.encode(List.filled(4 * 1024 * 1024, 32)));
        return r.close();
      };
      for (final path in ['/buyuk', '/akan', '/bomba']) {
        await expectLater(get(path), _fails(RoadmapLinkProblem.tooLarge), reason: path);
      }
    });

    test('gives up on a server that does not answer, and on one that cannot be reached', () async {
      routes['/sessiz'] = (r) => Completer<void>().future;
      await expectLater(get('/sessiz', timeout: const Duration(milliseconds: 300)), _fails(RoadmapLinkProblem.timeout));

      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(
        RoadmapLinkService.fetch(Uri.parse('http://127.0.0.1:$port/plan.json'), allowInsecure: true),
        _fails(RoadmapLinkProblem.network),
      );
    });
  });
}
