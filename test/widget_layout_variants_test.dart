import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pure XML tag representation containing tag name and raw attribute content.
class XmlTag {
  final String name;
  final String attributes;

  const XmlTag(this.name, this.attributes);
}

/// Parses XML tags while stripping comments and handling quote-enclosed strings.
List<XmlTag> parseXmlTags(String xml) {
  final clean = xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final tags = <XmlTag>[];
  var i = 0;
  final len = clean.length;

  while (i < len) {
    final start = clean.indexOf('<', i);
    if (start == -1) break;

    if (start + 1 >= len) break;
    final nextChar = clean[start + 1];
    // Skip closing tags, processing instructions (<?...>), and doctype/cdata (<!...>)
    if (nextChar == '/' || nextChar == '?' || nextChar == '!') {
      i = start + 2;
      continue;
    }

    var nameEnd = start + 1;
    while (nameEnd < len) {
      final c = clean[nameEnd];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '/' || c == '>') {
        break;
      }
      nameEnd++;
    }
    final tagName = clean.substring(start + 1, nameEnd);

    var curr = nameEnd;
    var inQuote = false;
    var quoteChar = '';
    while (curr < len) {
      final c = clean[curr];
      if (!inQuote) {
        if (c == '"' || c == "'") {
          inQuote = true;
          quoteChar = c;
        } else if (c == '>') {
          break;
        }
      } else {
        if (c == quoteChar) {
          inQuote = false;
        }
      }
      curr++;
    }

    final attributes = clean.substring(nameEnd, curr);
    tags.add(XmlTag(tagName, attributes));
    i = curr + 1;
  }
  return tags;
}

/// Extracts a mapping of android:id to view type (e.g. TextView, ListView) from layout XML.
Map<String, String> extractLayoutIds(String xmlContent) {
  final tags = parseXmlTags(xmlContent);
  final idRegex = RegExp(r'''android:id\s*=\s*["']@\+?id/([a-zA-Z0-9_]+)["']''');
  final result = <String, String>{};
  for (final tag in tags) {
    final match = idRegex.firstMatch(tag.attributes);
    if (match != null) {
      final id = match.group(1)!;
      result[id] = tag.name;
    }
  }
  return result;
}

/// Discovers layout stems that have _light or _dark variants (e.g. takip_widget).
Set<String> discoverLayoutVariantStems(Iterable<String> fileNames) {
  final stems = <String>{};
  for (final name in fileNames) {
    if (name.endsWith('_light.xml')) {
      stems.add(name.substring(0, name.length - '_light.xml'.length));
    } else if (name.endsWith('_dark.xml')) {
      stems.add(name.substring(0, name.length - '_dark.xml'.length));
    }
  }
  return stems;
}

/// Compares base layout with its _light and _dark variants.
/// Returns a list of mismatch error messages.
List<String> compareLayoutVariants({
  required String? baseXml,
  required String? lightXml,
  required String? darkXml,
  String baseName = 'base.xml',
  String lightName = 'light.xml',
  String darkName = 'dark.xml',
}) {
  final errors = <String>[];
  if (baseXml == null) {
    errors.add('Missing base layout file: $baseName');
  }
  if (lightXml == null) {
    errors.add('Missing light layout file: $lightName');
  }
  if (darkXml == null) {
    errors.add('Missing dark layout file: $darkName');
  }
  if (errors.isNotEmpty) return errors;

  final baseViews = extractLayoutIds(baseXml!);
  final lightViews = extractLayoutIds(lightXml!);
  final darkViews = extractLayoutIds(darkXml!);

  _compareViews(
    base: baseViews,
    variant: lightViews,
    variantName: lightName,
    baseName: baseName,
    errors: errors,
  );
  _compareViews(
    base: baseViews,
    variant: darkViews,
    variantName: darkName,
    baseName: baseName,
    errors: errors,
  );

  return errors;
}

void _compareViews({
  required Map<String, String> base,
  required Map<String, String> variant,
  required String variantName,
  required String baseName,
  required List<String> errors,
}) {
  final baseIds = base.keys.toSet();
  final variantIds = variant.keys.toSet();

  final missingInVariant = (baseIds.difference(variantIds)).toList()..sort();
  for (final id in missingInVariant) {
    errors.add("In '$variantName': missing ID '@+id/$id' present in '$baseName' (${base[id]})");
  }

  final extraInVariant = (variantIds.difference(baseIds)).toList()..sort();
  for (final id in extraInVariant) {
    errors.add("In '$variantName': extra ID '@+id/$id' (${variant[id]}) not present in '$baseName'");
  }

  final commonIds = (baseIds.intersection(variantIds)).toList()..sort();
  for (final id in commonIds) {
    if (base[id] != variant[id]) {
      errors.add(
        "In '$variantName': view type mismatch for ID '@+id/$id' (got '${variant[id]}', expected '${base[id]}' from '$baseName')",
      );
    }
  }
}

/// Checks that every night drawable has base, _light, and _dark variants in drawable/.
List<String> checkDrawableVariants({
  required Iterable<String> nightDrawableFileNames,
  required Set<String> drawableFileNames,
}) {
  final errors = <String>[];
  final sortedNight = nightDrawableFileNames.toList()..sort();
  for (final nightFile in sortedNight) {
    final stem = nightFile.endsWith('.xml')
        ? nightFile.substring(0, nightFile.length - 4)
        : nightFile;
    final lightFile = '${stem}_light.xml';
    final darkFile = '${stem}_dark.xml';
    final baseFile = '$stem.xml';

    if (!drawableFileNames.contains(lightFile)) {
      errors.add("In res/drawable: missing light variant '$lightFile' for night drawable '$nightFile'");
    }
    if (!drawableFileNames.contains(darkFile)) {
      errors.add("In res/drawable: missing dark variant '$darkFile' for night drawable '$nightFile'");
    }
    if (!drawableFileNames.contains(baseFile)) {
      errors.add("In res/drawable: missing base drawable '$baseFile' for night drawable '$nightFile'");
    }
  }
  return errors;
}

/// Extracts color names defined in a colors.xml file.
Set<String> extractColorNames(String xmlContent) {
  final clean = xmlContent.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final colorRegex = RegExp(r'''<color\s+[^>]*name\s*=\s*["']([a-zA-Z0-9_]+)["']''');
  return colorRegex.allMatches(clean).map((m) => m.group(1)!).toSet();
}

/// Checks that every color in values-night/colors.xml is also defined in values/colors.xml.
List<String> checkColorsConsistency({
  required String baseColorsXml,
  required String nightColorsXml,
}) {
  final baseColors = extractColorNames(baseColorsXml);
  final nightColors = extractColorNames(nightColorsXml);
  final errors = <String>[];

  final missingInBase = (nightColors.difference(baseColors)).toList()..sort();
  for (final color in missingInBase) {
    errors.add("Color '$color' defined in values-night/colors.xml is missing in values/colors.xml");
  }
  return errors;
}

/// Locates android/app/src/main/res directory starting from current working directory.
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

void main() {
  group('Synthetic layout and resource consistency checks (pure function unit tests)', () {
    const baseSample = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title"
        android:text="Title" />
    <TextView
        android:id="@+id/btn_action"
        android:text="Action" />
</LinearLayout>
''';

    const lightSampleMatching = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title"
        android:textColor="@color/widget_title_light" />
    <TextView
        android:id="@+id/btn_action"
        android:textColor="@color/widget_button_text_light" />
</LinearLayout>
''';

    const darkSampleMatching = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title"
        android:textColor="@color/widget_title_dark" />
    <TextView
        android:id="@+id/btn_action"
        android:textColor="@color/widget_button_text_dark" />
</LinearLayout>
''';

    test('passes when base, light, and dark layouts have identical ID sets and view types', () {
      final errors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: lightSampleMatching,
        darkXml: darkSampleMatching,
        baseName: 'sample.xml',
        lightName: 'sample_light.xml',
        darkName: 'sample_dark.xml',
      );
      expect(errors, isEmpty);
    });

    test('detects missing copy (base, light, or dark is null)', () {
      final missingBaseErrors = compareLayoutVariants(
        baseXml: null,
        lightXml: lightSampleMatching,
        darkXml: darkSampleMatching,
        baseName: 'sample.xml',
      );
      expect(missingBaseErrors, contains('Missing base layout file: sample.xml'));

      final missingLightErrors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: null,
        darkXml: darkSampleMatching,
        lightName: 'sample_light.xml',
      );
      expect(missingLightErrors, contains('Missing light layout file: sample_light.xml'));

      final missingDarkErrors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: lightSampleMatching,
        darkXml: null,
        darkName: 'sample_dark.xml',
      );
      expect(missingDarkErrors, contains('Missing dark layout file: sample_dark.xml'));
    });

    test('detects missing ID in variant layout', () {
      const lightMissingBtn = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title" />
</LinearLayout>
''';

      final errors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: lightMissingBtn,
        darkXml: darkSampleMatching,
        baseName: 'sample.xml',
        lightName: 'sample_light.xml',
        darkName: 'sample_dark.xml',
      );

      expect(errors.any((e) => e.contains("In 'sample_light.xml': missing ID '@+id/btn_action' present in 'sample.xml' (TextView)")), isTrue);
    });

    test('detects extra ID in variant layout not present in base', () {
      const darkWithExtra = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title" />
    <TextView
        android:id="@+id/btn_action" />
    <ImageView
        android:id="@+id/extra_icon" />
</LinearLayout>
''';

      final errors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: lightSampleMatching,
        darkXml: darkWithExtra,
        baseName: 'sample.xml',
        lightName: 'sample_light.xml',
        darkName: 'sample_dark.xml',
      );

      expect(errors.any((e) => e.contains("In 'sample_dark.xml': extra ID '@+id/extra_icon' (ImageView) not present in 'sample.xml'")), isTrue);
    });

    test('detects view type mismatch for the same ID', () {
      const darkTypeMismatch = '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/container">
    <TextView
        android:id="@+id/title" />
    <Button
        android:id="@+id/btn_action" />
</LinearLayout>
''';

      final errors = compareLayoutVariants(
        baseXml: baseSample,
        lightXml: lightSampleMatching,
        darkXml: darkTypeMismatch,
        baseName: 'sample.xml',
        lightName: 'sample_light.xml',
        darkName: 'sample_dark.xml',
      );

      expect(
        errors.any(
          (e) => e.contains(
            "In 'sample_dark.xml': view type mismatch for ID '@+id/btn_action' (got 'Button', expected 'TextView' from 'sample.xml')",
          ),
        ),
        isTrue,
      );
    });

    test('detects missing light, dark, and base drawables in checkDrawableVariants', () {
      final nightDrawables = ['widget_test_bg.xml'];
      // Only has base and light, missing dark
      final errorsMissingDark = checkDrawableVariants(
        nightDrawableFileNames: nightDrawables,
        drawableFileNames: {'widget_test_bg.xml', 'widget_test_bg_light.xml'},
      );
      expect(
        errorsMissingDark,
        contains("In res/drawable: missing dark variant 'widget_test_bg_dark.xml' for night drawable 'widget_test_bg.xml'"),
      );

      // Missing base
      final errorsMissingBase = checkDrawableVariants(
        nightDrawableFileNames: nightDrawables,
        drawableFileNames: {'widget_test_bg_light.xml', 'widget_test_bg_dark.xml'},
      );
      expect(
        errorsMissingBase,
        contains("In res/drawable: missing base drawable 'widget_test_bg.xml' for night drawable 'widget_test_bg.xml'"),
      );
    });

    test('detects colors in values-night/colors.xml missing from values/colors.xml', () {
      const baseColors = '''
<resources>
    <color name="color_a">#FFFFFF</color>
</resources>
''';
      const nightColors = '''
<resources>
    <color name="color_a">#000000</color>
    <color name="color_missing">#123456</color>
</resources>
''';

      final errors = checkColorsConsistency(
        baseColorsXml: baseColors,
        nightColorsXml: nightColors,
      );
      expect(errors, contains("Color 'color_missing' defined in values-night/colors.xml is missing in values/colors.xml"));
    });
  });

  group('Real Android resources consistency (android/app/src/main/res)', () {
    late Directory resDir;
    late Directory layoutDir;
    late Directory drawableDir;
    late Directory drawableNightDir;
    late Directory valuesDir;
    late Directory valuesNightDir;

    setUpAll(() {
      resDir = findResDirectory();
      layoutDir = Directory('${resDir.path}/layout');
      drawableDir = Directory('${resDir.path}/drawable');
      drawableNightDir = Directory('${resDir.path}/drawable-night');
      valuesDir = Directory('${resDir.path}/values');
      valuesNightDir = Directory('${resDir.path}/values-night');

      expect(layoutDir.existsSync(), isTrue, reason: 'res/layout directory must exist');
      expect(drawableDir.existsSync(), isTrue, reason: 'res/drawable directory must exist');
      expect(drawableNightDir.existsSync(), isTrue, reason: 'res/drawable-night directory must exist');
      expect(valuesDir.existsSync(), isTrue, reason: 'res/values directory must exist');
      expect(valuesNightDir.existsSync(), isTrue, reason: 'res/values-night directory must exist');
    });

    test('all layout variants (_light, _dark) match their base layout in IDs and view types', () {
      final layoutFiles = layoutDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xml'))
          .map((f) => f.uri.pathSegments.last)
          .toList();

      final stems = discoverLayoutVariantStems(layoutFiles);
      expect(stems, isNotEmpty, reason: 'At least one layout with theme variants must exist');

      final allErrors = <String>[];
      for (final stem in (stems.toList()..sort())) {
        final baseFile = File('${layoutDir.path}/$stem.xml');
        final lightFile = File('${layoutDir.path}/${stem}_light.xml');
        final darkFile = File('${layoutDir.path}/${stem}_dark.xml');

        final baseXml = baseFile.existsSync() ? baseFile.readAsStringSync() : null;
        final lightXml = lightFile.existsSync() ? lightFile.readAsStringSync() : null;
        final darkXml = darkFile.existsSync() ? darkFile.readAsStringSync() : null;

        final stemErrors = compareLayoutVariants(
          baseXml: baseXml,
          lightXml: lightXml,
          darkXml: darkXml,
          baseName: '$stem.xml',
          lightName: '${stem}_light.xml',
          darkName: '${stem}_dark.xml',
        );

        allErrors.addAll(stemErrors);
      }

      expect(
        allErrors,
        isEmpty,
        reason: 'Layout variant inconsistencies found:\n${allErrors.join('\n')}',
      );
    });

    test('all drawables in drawable-night have base, _light, and _dark variants in drawable', () {
      final nightFiles = drawableNightDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xml'))
          .map((f) => f.uri.pathSegments.last)
          .toList();

      expect(nightFiles, isNotEmpty, reason: 'drawable-night must contain at least one drawable');

      final drawableFiles = drawableDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xml'))
          .map((f) => f.uri.pathSegments.last)
          .toSet();

      final errors = checkDrawableVariants(
        nightDrawableFileNames: nightFiles,
        drawableFileNames: drawableFiles,
      );

      expect(
        errors,
        isEmpty,
        reason: 'Drawable variant inconsistencies found:\n${errors.join('\n')}',
      );
    });

    test('all colors in values-night/colors.xml are also defined in values/colors.xml', () {
      final nightColorsFile = File('${valuesNightDir.path}/colors.xml');
      final baseColorsFile = File('${valuesDir.path}/colors.xml');

      expect(nightColorsFile.existsSync(), isTrue, reason: 'values-night/colors.xml must exist');
      expect(baseColorsFile.existsSync(), isTrue, reason: 'values/colors.xml must exist');

      final errors = checkColorsConsistency(
        baseColorsXml: baseColorsFile.readAsStringSync(),
        nightColorsXml: nightColorsFile.readAsStringSync(),
      );

      expect(
        errors,
        isEmpty,
        reason: 'Color definition inconsistencies found:\n${errors.join('\n')}',
      );
    });
  });
}
