import 'dart:io';

import 'package:flutter/services.dart';

/// Widget tests draw every glyph of the default test font as a full square, which is far wider than real
/// text. Width checks therefore load the app's bundled Noto Sans under the family Material uses on Android.
Future<void> loadRealFont() async {
  final loader = FontLoader('Roboto');
  for (final file in ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf']) {
    loader.addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
  }
  await loader.load();
}
