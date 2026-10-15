import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/ui/activity_page.dart';

void seed(List<Activity> activities, List<Entry> entries) {
  store.activities
    ..clear()
    ..addEntries([for (final a in activities) MapEntry(a.id, a)]);
  store.entries = [...entries]..sort((a, b) => a.ts.compareTo(b.ts));
  store.clearHabitStreakCache();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  setUp(() {
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
  });

  tearDown(() {
    seed(const [], const []);
  });

  testWidgets('ActivityPage renders duration metrics for time-based activity', (tester) async {
    final act = Activity(id: 1, name: 'Ders Çalışma', emoji: '📚', createdAt: 0);
    final now = DateTime.now();

    final t1 = now.subtract(const Duration(hours: 3));
    final t2 = now.subtract(const Duration(hours: 1));

    seed([act], [
      Entry(
        id: 1,
        activityId: act.id,
        ts: t1.millisecondsSinceEpoch,
        endTs: t1.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
      ),
      Entry(
        id: 2,
        activityId: act.id,
        ts: t2.millisecondsSinceEpoch,
        endTs: t2.add(const Duration(minutes: 75)).millisecondsSinceEpoch,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ActivityPage(activity: act),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ders Çalışma'), findsWidgets);
    expect(find.text('Toplam Süre'), findsOneWidget);
    expect(find.text('Ortalama Oturum'), findsOneWidget);
    expect(find.text('2 sa'), findsOneWidget); // 45 + 75 = 120 mins = 2 sa
    expect(find.text('1 sa'), findsOneWidget); // avg 60 mins = 1 sa
  });

  testWidgets('ActivityPage renders quantity metrics for measure/volume activity', (tester) async {
    final act = Activity(id: 2, name: 'Su İçme', emoji: '💧', createdAt: 0);
    final now = DateTime.now();

    seed([act], [
      Entry(
        id: 1,
        activityId: act.id,
        ts: now.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
        value: 0.5,
        unitId: 'l',
      ),
      Entry(
        id: 2,
        activityId: act.id,
        ts: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        value: 1.0,
        unitId: 'l',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ActivityPage(activity: act),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Su İçme'), findsWidgets);
    expect(find.text('Toplam Miktar'), findsOneWidget);
    expect(find.text('Kayıt Başına'), findsOneWidget);
    expect(find.text('1,5 L'), findsWidgets);
  });

  testWidgets('ActivityPage renders event metrics and severity card for symptom/event activity', (tester) async {
    final act = Activity(id: 3, name: 'Baş Ağrısı', emoji: '🤕', createdAt: 0);
    final now = DateTime.now();

    seed([act], [
      Entry(
        id: 1,
        activityId: act.id,
        ts: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        note: 'Şiddet 8/10 zonklama',
      ),
      Entry(
        id: 2,
        activityId: act.id,
        ts: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        note: 'Hafif sızı 4/10',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ActivityPage(activity: act),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Baş Ağrısı'), findsWidgets);
    expect(find.text('Toplam Olay'), findsOneWidget);
    expect(find.text('Ortalama Aralık'), findsOneWidget);
    expect(find.text('Şiddet ve Belirti Eğilimi'), findsOneWidget);
    expect(find.text('Şiddet Azalıyor'), findsOneWidget);
  });

  testWidgets('ActivityPage allows user to switch format views via segmented buttons', (tester) async {
    final act = Activity(id: 4, name: 'Kitap Okuma', emoji: '📖', createdAt: 0);
    final now = DateTime.now();
    final t1 = now.subtract(const Duration(hours: 2));

    seed([act], [
      Entry(
        id: 1,
        activityId: act.id,
        ts: t1.millisecondsSinceEpoch,
        endTs: t1.add(const Duration(minutes: 60)).millisecondsSinceEpoch,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ActivityPage(activity: act),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Toplam Süre'), findsOneWidget);

    final eventSegment = find.text('Olay');
    expect(eventSegment, findsOneWidget);
    await tester.tap(eventSegment);
    await tester.pumpAndSettle();

    expect(find.text('Toplam Olay'), findsOneWidget);
    expect(find.text('Aktif Günler'), findsOneWidget);
  });
}
