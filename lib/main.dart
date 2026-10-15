import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/store.dart';
import 'logic/l10n.dart';
import 'ui/goals_page.dart';
import 'ui/manage_page.dart';
import 'ui/startup_recovery_page.dart';
import 'ui/stats_page.dart';
import 'ui/today_page.dart';
import 'services/notification_service.dart';
import 'services/store_sync.dart';
import 'widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  await initializeDateFormatting('en_US');
  Intl.defaultLocale = 'tr_TR';
  await NotificationService.init();
  // Okunamayan bir veritabanı uygulamanın hiç açılmamasına yol açmasın: hata kurtarma ekranında gösterilir.
  Object? startupError;
  try {
    await store.load();
  } catch (e, st) {
    debugPrint('Açılışta veriler yüklenemedi: $e\n$st');
    startupError = e;
  }
  StoreSync.listen(store);
  store.addListener(WidgetSync.schedule);
  WidgetSync.push();
  unawaited(HomeWidget.registerInteractivityCallback(widgetBackgroundCallback));
  runApp(TakipApp(startupError: startupError));
}

class TakipApp extends StatelessWidget {
  /// Açılışta veriler yüklenemediyse hata; ana ekran yerine kurtarma ekranı açılır.
  final Object? startupError;
  const TakipApp({super.key, this.startupError});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3D6FE0), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = startupError;
    return AnimatedBuilder(
      animation: Listenable.merge([store.appThemeNotifier, store.appLanguageNotifier]),
      builder: (context, _) {
        final loc = store.language == AppLanguage.en
            ? const Locale('en', 'US')
            : const Locale('tr', 'TR');
        return MaterialApp(
          title: 'Takip',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          locale: loc,
          supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: error == null ? const HomeShell() : _StartupGate(error: error),
        );
      },
    );
  }
}

/// Veriler yüklenene kadar kurtarma ekranını, yüklendikten sonra ana ekranı gösterir.
class _StartupGate extends StatelessWidget {
  final Object error;
  const _StartupGate({required this.error});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => store.loaded ? const HomeShell() : StartupRecoveryPage(error: error),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _focusComposer = ValueNotifier<int>(0);
  StreamSubscription<Uri?>? _widgetSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetLaunch);
    _widgetSub = HomeWidget.widgetClicked.listen(_onWidgetLaunch);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Widget üzerinden eklenenleri ve gün değişimini yakalamak için
    if (state == AppLifecycleState.resumed) store.load();
  }

  void _onWidgetLaunch(Uri? uri) {
    if (uri == null || !mounted) return;
    setState(() => _tab = 0);
    if (uri.host == 'add') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusComposer.value++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store.appLanguageNotifier,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              TodayPage(focusRequest: _focusComposer),
              const GoalsPage(),
              const StatsPage(),
              const ManagePage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              FocusScope.of(context).unfocus();
              setState(() => _tab = i);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.today_outlined),
                selectedIcon: const Icon(Icons.today),
                label: s.tabToday,
              ),
              NavigationDestination(
                icon: const Icon(Icons.flag_outlined),
                selectedIcon: const Icon(Icons.flag),
                label: s.tabGoals,
              ),
              NavigationDestination(
                icon: const Icon(Icons.insights_outlined),
                selectedIcon: const Icon(Icons.insights),
                label: s.tabStats,
              ),
              NavigationDestination(
                icon: const Icon(Icons.tune_outlined),
                selectedIcon: const Icon(Icons.tune),
                label: s.tabSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}
