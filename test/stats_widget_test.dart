import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/ui/stats_page.dart';

/// Puts activities and entries into the in-memory store; the page only reads.
void seed(List<Activity> activities, List<Entry> entries) {
  store.activities
    ..clear()
    ..addEntries([for (final a in activities) MapEntry(a.id, a)]);
  store.entries = [...entries]..sort((a, b) => a.ts.compareTo(b.ts));
  store.clearHabitStreakCache();
}

/// An entry today at [minute] past midnight.
Entry today(int id, int activityId, int minute, {double? value, String? unit}) {
  final now = DateTime.now();
  return Entry(
    id: id,
    activityId: activityId,
    ts: DateTime(now.year, now.month, now.day, 0, minute).millisecondsSinceEpoch,
    qty: 1,
    value: value,
    unitId: unit,
  );
}

Future<void> pumpStats(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: StatsPage()));
  await tester.pumpAndSettle();
}

Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
Finder filter(String label) => find.widgetWithText(FilterChip, label);
IconButton button(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, tooltip == 'Sonraki'
        ? Icons.chevron_right_rounded
        : Icons.chevron_left_rounded));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  tearDown(() {
    seed(const [], const []);
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
  });

  final ders = Activity(id: 1, name: 'Ders', createdAt: 0);
  final kosu = Activity(id: 2, name: 'Koşu', createdAt: 0);
  final sinav = Activity(id: 3, name: 'Şınav', createdAt: 0);

  testWidgets('Pumps StatsPage without errors', (tester) async {
    seed([ders], [today(1, 1, 1, value: 30, unit: 'dk')]);
    await pumpStats(tester);

    expect(find.text('İstatistikler & Özet'), findsOneWidget);
  });

  testWidgets('the day view charts the hours of the day, not weeks', (tester) async {
    seed([ders], [today(1, 1, 1), today(2, 1, 2)]);
    await pumpStats(tester);

    await tester.tap(find.text('Günlük'));
    await tester.pumpAndSettle();

    expect(find.text('Saatlere Göre'), findsOneWidget);
    expect(find.text('En Yoğun Saat'), findsOneWidget);
    expect(find.text('00:00–01:00'), findsOneWidget);
    expect(find.textContaining('. Hafta'), findsNothing);
    expect(tester.widget<BarChart>(find.byType(BarChart)).data.barGroups, hasLength(24));
    // A daily average says nothing about a single day.
    expect(find.text('Günlük Ortalama'), findsNothing);
  });

  testWidgets('every slice of the period gets a bar', (tester) async {
    seed([ders], [today(1, 1, 1)]);
    await pumpStats(tester);
    int bars() => tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length;
    final now = DateTime.now();

    expect(bars(), 7);
    expect(find.text('Günlere Göre'), findsOneWidget);

    await tester.tap(find.text('Aylık'));
    await tester.pumpAndSettle();
    expect(bars(), DateTime(now.year, now.month + 1, 0).day);

    await tester.tap(find.text('Yıllık'));
    await tester.pumpAndSettle();
    expect(bars(), 12);
    expect(find.text('Aylara Göre'), findsOneWidget);
    expect(find.text('En Yoğun Ay'), findsOneWidget);
  });

  testWidgets('one activity is summed up in its own unit', (tester) async {
    seed([ders, kosu], [
      today(1, 1, 1, value: 30, unit: 'dk'),
      today(2, 1, 2, value: 90, unit: 'dk'),
      today(3, 2, 3, value: 5, unit: 'km'),
    ]);
    await pumpStats(tester);

    // All activities together are counted by entries.
    expect(find.text('3'), findsWidgets);
    expect(tester.widget<ChoiceChip>(chip('Kayıt')).selected, isTrue);

    await tester.tap(filter('Ders (2)'));
    await tester.pumpAndSettle();

    expect(find.text('2 sa'), findsWidgets, reason: 'the total, the daily average and the busiest day');
    expect(tester.widget<ChoiceChip>(chip('Süre')).selected, isTrue, reason: 'the chart follows the activity');
    expect(chip('Mesafe'), findsNothing);
    expect(find.textContaining('filtresi aktif'), findsNothing);

    // The page is the first scrollable; the filter chips and the calendar scroll too.
    await tester.scrollUntilVisible(find.text('Tüm aktivitelere dön'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Tüm aktivitelere dön'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(filter('Tümü (3)')).selected, isTrue);
  });

  testWidgets('the chart offers the measures the entries have', (tester) async {
    seed([kosu, sinav], [
      today(1, 2, 1, value: 5, unit: 'km'),
      today(2, 3, 2, value: 20, unit: 'adet'),
    ]);
    await pumpStats(tester);

    expect(chip('Kayıt'), findsOneWidget);
    expect(chip('Mesafe'), findsOneWidget);
    expect(chip('Hacim'), findsNothing, reason: 'nothing was measured in litres');
    expect(chip('Adet'), findsNothing, reason: 'pieces of different activities do not add up');
    expect(find.textContaining('adet'), findsOneWidget, reason: 'only the row of the activity itself');

    await tester.tap(filter('Şınav (1)'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip('Adet')).selected, isTrue);

    // The choice made for one activity does not carry over to the next.
    await tester.tap(chip('Kayıt'));
    await tester.pumpAndSettle();
    await tester.tap(filter('Koşu (1)'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip('Mesafe')).selected, isTrue);
  });

  testWidgets('the period cannot be moved into the future', (tester) async {
    seed([ders], [today(1, 1, 1)]);
    await pumpStats(tester);

    expect(button(tester, 'Sonraki').onPressed, isNull);
    expect(find.text('Bugün'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(button(tester, 'Sonraki').onPressed, isNotNull);
    expect(find.text('Bu dönemde kayıt yok.'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing, reason: 'an empty period draws no empty charts');

    // The title brings the current period back.
    await tester.tap(find.text('Bugün'));
    await tester.pumpAndSettle();
    expect(button(tester, 'Sonraki').onPressed, isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('dates and labels follow the language', (tester) async {
    seed([ders], [today(1, 1, 1)]);
    store.language = AppLanguage.en;
    strings.value = const AppStrings(AppLanguage.en);
    await pumpStats(tester);

    final now = DateTime.now();
    final sunday = DateTime(now.year, now.month, now.day - (now.weekday - 1) + 6);
    expect(find.textContaining(DateFormat('d MMM', 'en_US').format(sunday)), findsOneWidget);
    expect(find.text('By Day'), findsOneWidget);
    expect(find.text('Busiest Day'), findsOneWidget);
    expect(find.text(DateFormat.EEEE('en_US').format(now)), findsOneWidget);
    expect(find.text('1 entry'), findsWidgets);
  });

  testWidgets('exporting is offered once and says what it covers', (tester) async {
    seed([ders], [today(1, 1, 1)]);
    await pumpStats(tester);

    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Tüm kayıtlar dışa aktarılır'), findsOneWidget);
    expect(find.text('PDF raporu'), findsOneWidget);
    expect(find.text('Excel tablosu (CSV)'), findsOneWidget);
  });
}
