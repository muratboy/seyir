import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

import 'support/real_db.dart';

final _turkishCharRegex = RegExp(r'[çÇğĞıİöÖşŞ]');

Directory findResDirectory() {
  var dir = Directory.current;
  while (true) {
    final candidate = Directory('${dir.path}/android/app/src/main/res');
    if (candidate.existsSync()) {
      return candidate;
    }
    if (dir.path == dir.parent.path) break;
    dir = dir.parent;
  }
  final fallback = Directory('android/app/src/main/res');
  if (fallback.existsSync()) return fallback;
  fail('Could not locate android/app/src/main/res directory');
}

Directory findKotlinDirectory() {
  var dir = Directory.current;
  while (true) {
    final candidate = Directory('${dir.path}/android/app/src/main/kotlin');
    if (candidate.existsSync()) {
      return candidate;
    }
    if (dir.path == dir.parent.path) break;
    dir = dir.parent;
  }
  final fallback = Directory('android/app/src/main/kotlin');
  if (fallback.existsSync()) return fallback;
  fail('Could not locate android/app/src/main/kotlin directory');
}

List<String> extractStringKeys(String xmlContent) {
  final stringRegex = RegExp(r'''<string\s+name=["']([a-zA-Z0-9_]+)["']''');
  return stringRegex.allMatches(xmlContent).map((m) => m.group(1)!).toList();
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  group('Android resource and layout localization tests', () {
    late Directory resDir;
    late Directory kotlinDir;

    setUpAll(() {
      resDir = findResDirectory();
      kotlinDir = findKotlinDirectory();
    });

    test('values/strings.xml contains no Turkish-specific characters', () {
      final file = File('${resDir.path}/values/strings.xml');
      expect(file.existsSync(), isTrue, reason: 'values/strings.xml must exist');
      final content = file.readAsStringSync();
      final matches = _turkishCharRegex.allMatches(content).map((m) => m.group(0)).toList();
      expect(matches, isEmpty, reason: 'values/strings.xml should not contain Turkish characters');
    });

    test('values-tr/strings.xml exists and has identical keys to values/strings.xml', () {
      final enFile = File('${resDir.path}/values/strings.xml');
      final trFile = File('${resDir.path}/values-tr/strings.xml');

      expect(trFile.existsSync(), isTrue, reason: 'values-tr/strings.xml must exist');
      final enKeys = extractStringKeys(enFile.readAsStringSync());
      final trKeys = extractStringKeys(trFile.readAsStringSync());

      expect(enKeys, isNotEmpty);
      expect(trKeys, equals(enKeys), reason: 'values-tr/strings.xml must define the exact same keys in the same order');
    });

    test('no other values-*/strings.xml exists', () {
      final otherStringFiles = resDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.uri.pathSegments.reversed.skip(1).first.startsWith('values-') &&
                        !d.uri.pathSegments.reversed.skip(1).first.endsWith('values-tr') &&
                        !d.uri.pathSegments.reversed.skip(1).first.endsWith('values-night'))
          .expand((d) => d.listSync())
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last == 'strings.xml')
          .map((f) => f.path)
          .toList();

      expect(otherStringFiles, isEmpty, reason: 'Only values/ and values-tr/ should have strings.xml');
    });

    test('res/layout/*.xml text, hint, and contentDescription attributes contain no Turkish characters', () {
      final layoutDir = Directory('${resDir.path}/layout');
      final violations = <String>[];

      for (final entity in layoutDir.listSync()) {
        if (entity is File && entity.path.endsWith('.xml')) {
          final content = entity.readAsStringSync();
          final attrRegex = RegExp(r'''android:(?:text|hint|contentDescription)=["']([^"']*)["']''');
          for (final match in attrRegex.allMatches(content)) {
            final val = match.group(1)!;
            if (_turkishCharRegex.hasMatch(val)) {
              violations.add('${entity.uri.pathSegments.last}: $val');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: 'Found Turkish-specific characters hardcoded in layout attributes:\n${violations.join('\n')}');
    });

    test('Kotlin string literals with Turkish characters are guarded by isTr on the same line', () {
      final violations = <String>[];

      for (final entity in kotlinDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.kt')) {
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            final clean = line.trim();
            if (clean.startsWith('//') || clean.startsWith('/*') || clean.startsWith('*')) {
              continue;
            }
            final stringLiteralRegex = RegExp(r'''"([^"\\]*(?:\\.[^"\\]*)*)"''');
            for (final match in stringLiteralRegex.allMatches(line)) {
              final literal = match.group(1)!;
              if (_turkishCharRegex.hasMatch(literal)) {
                if (!line.contains('isTr')) {
                  violations.add('${entity.uri.pathSegments.last}:${i + 1}: $literal');
                }
              }
            }
          }
        }
      }

      expect(violations, isEmpty, reason: 'Found unguarded Turkish string literals in Kotlin without isTr on the same line:\n${violations.join('\n')}');
    });

    test('values/strings.xml tile_quick_add matches English settings instruction name', () {
      final stringsXmlFile = File('${resDir.path}/values/strings.xml');
      final stringsXmlContent = stringsXmlFile.readAsStringSync();
      final tileMatch = RegExp(r'<string\s+name="tile_quick_add">([^<]+)</string>').firstMatch(stringsXmlContent);
      expect(tileMatch, isNotNull, reason: 'tile_quick_add must exist in values/strings.xml');
      final tileQuickAdd = tileMatch!.group(1);

      var dir = Directory.current;
      File? settingsFile;
      while (true) {
        final candidate = File('${dir.path}/lib/ui/settings_pages.dart');
        if (candidate.existsSync()) {
          settingsFile = candidate;
          break;
        }
        if (dir.path == dir.parent.path) break;
        dir = dir.parent;
      }
      expect(settingsFile, isNotNull, reason: 'lib/ui/settings_pages.dart must exist');
      final settingsContent = settingsFile!.readAsStringSync();
      final instructionMatch = RegExp(r'Drag\s+"([^"]+)"\s+into your active tiles').firstMatch(settingsContent);
      expect(instructionMatch, isNotNull, reason: 'Settings instructions must mention active tiles drag prompt');
      final expectedName = instructionMatch!.group(1);

      expect(tileQuickAdd, equals(expectedName));
    });

    test('no occurrences of "Quick Record" in Android resources or Kotlin sources', () {
      final violations = <String>[];

      for (final entity in resDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.xml')) {
          final content = entity.readAsStringSync();
          if (content.contains('Quick Record')) {
            violations.add(entity.path);
          }
        }
      }

      for (final entity in kotlinDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.kt')) {
          final content = entity.readAsStringSync();
          if (content.contains('Quick Record')) {
            violations.add(entity.path);
          }
        }
      }

      expect(violations, isEmpty, reason: 'Found "Quick Record" in:\n${violations.join('\n')}');
    });
  });

  group('Dart widget payload localization tests', () {
    test('when language is English, widgetPayload contains no Turkish characters and isTr is false', () async {
      await store.setLanguage(AppLanguage.en);
      final payload = store.widgetPayload();

      expect(payload['isTr'], isFalse);

      final singleTitle = payload['single_title'] as String?;
      final singleSub = payload['single_sub'] as String?;
      expect(_turkishCharRegex.hasMatch(singleTitle ?? ''), isFalse, reason: 'single_title has Turkish: $singleTitle');
      expect(_turkishCharRegex.hasMatch(singleSub ?? ''), isFalse, reason: 'single_sub has Turkish: $singleSub');

      final items = payload['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map<String, Object?>) {
          final sub = item['s'] as String? ?? '';
          expect(_turkishCharRegex.hasMatch(sub), isFalse, reason: 'item sub has Turkish: $sub');
        }
      }
    });

    test('when language is English, todoWidgetPayload contains no Turkish characters and isTr is false', () async {
      await store.setLanguage(AppLanguage.en);
      final payload = store.todoWidgetPayload();

      expect(payload['isTr'], isFalse);

      final items = payload['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map<String, Object?>) {
          final sub = item['sub'] as String? ?? '';
          expect(_turkishCharRegex.hasMatch(sub), isFalse, reason: 'todo sub has Turkish: $sub');
        }
      }
    });
  });
}
