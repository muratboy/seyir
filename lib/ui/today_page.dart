import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import '../services/nl_parser.dart';
import 'common.dart';
import 'components/active_timer_card.dart';
import 'components/today_summary_card.dart';
import 'components/today_todos_card.dart';
import 'components/today_health_panel.dart';
import 'components/today_quick_shortcuts.dart';
import 'components/today_routines_panel.dart';
import 'components/today_roadmap_panel.dart';
import 'components/today_timeline.dart';
import 'search_page.dart';
import 'voice_dialog.dart';
import 'app_font.dart';

class TodayPage extends StatelessWidget {
  final ValueNotifier<int> focusRequest;
  final ValueNotifier<int>? voiceRequest;
  const TodayPage({super.key, required this.focusRequest, this.voiceRequest});

  @override
  Widget build(BuildContext context) {
    // Sayfanın kendi bildirim alanı vardır: snackbar'lar alta sabitlenmiş giriş kutusunun üstünde belirir,
    // onu örtmez.
    return ScaffoldMessenger(child: _TodayView(focusRequest: focusRequest, voiceRequest: voiceRequest));
  }
}

/// Giriş kutusuna yazılan metnin gönder düğmesine basılınca neye dönüşeceği.
class _ComposerPlan {
  final NlParseResult parsed;

  /// Metnin bağlandığı kayıtlı aktivite; null ise [NlParseResult.activityName] adıyla yenisi açılır.
  final Activity? existing;
  final int? measureId;
  final double qty;

  /// Metin sayaç komutu olarak da okunabiliyor: önizleme öbür okumaya geçmeyi önerir.
  final bool canBeCommand;

  const _ComposerPlan({
    required this.parsed,
    required this.existing,
    required this.measureId,
    required this.qty,
    required this.canBeCommand,
  });

  /// Sayaç başlatılacaksa modu ve süresi; kayıt eklenecekse null.
  ({String mode, int targetMs})? get timer => parsed.timerCommand;
}

class _ComposerModeSelector extends StatelessWidget {
  final bool isEntrySelected;
  final bool isTodoSelected;
  final ValueChanged<bool> onChanged;

  const _ComposerModeSelector({
    required this.isEntrySelected,
    required this.isTodoSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final isTr = s.isTr;

    Widget buildSegment({
      required String label,
      required bool selected,
      required bool forTodo,
      required Key key,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            canRequestFocus: false,
            onTap: () => onChanged(forTodo),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: AppFont.micro,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 6,
          bottom: 6,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4), width: 0.8),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 2),
            buildSegment(
              label: isTr ? 'Kayıt' : 'Entry',
              selected: isEntrySelected,
              forTodo: false,
              key: const Key('mode-selector-entry'),
            ),
            const SizedBox(width: 2),
            buildSegment(
              label: isTr ? 'Yapılacak' : 'To-do',
              selected: isTodoSelected,
              forTodo: true,
              key: const Key('mode-selector-todo'),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ],
    );
  }
}

/// Gönder düğmesine basılınca ne olacağını söyleyen satır. Uygulama yazılanı sessizce yorumlamaz: sayaç
/// mı başlayacak, hangi aktiviteye ne kadar eklenecek, önce burada görünür. Metin iki türlü okunabiliyorsa
/// [otherLabel] öbür okumaya geçirir.
class _ComposerPreview extends StatelessWidget {
  final bool startsTimer;
  final String text;
  final String? otherLabel;
  final VoidCallback onOther;
  final VoidCallback? onToggleOptions;
  final bool optionsOpen;
  final Widget? timeChip;

  const _ComposerPreview({
    required this.startsTimer,
    required this.text,
    required this.otherLabel,
    required this.onOther,
    this.onToggleOptions,
    this.optionsOpen = false,
    this.timeChip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTr = strings.value.isTr;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(
            startsTimer ? Icons.timer_outlined : Icons.add_task_rounded,
            size: 16,
            color: startsTimer ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: onToggleOptions,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Text(
                  text,
                  key: const Key('composer-preview'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          if (timeChip != null) ...[
            const SizedBox(width: 4),
            timeChip!,
          ],
          if (onToggleOptions != null && !startsTimer)
            IconButton(
              icon: Icon(
                optionsOpen ? Icons.expand_less : Icons.tune_rounded,
                size: 18,
                color: optionsOpen ? scheme.primary : scheme.onSurfaceVariant,
              ),
              tooltip: isTr ? 'Ayrıntılar' : 'Details',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onToggleOptions,
            ),
          if (otherLabel != null)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onOther,
              child: Text(otherLabel!),
            ),
        ],
      ),
    );
  }
}

class _TodayView extends StatefulWidget {
  final ValueNotifier<int> focusRequest;
  final ValueNotifier<int>? voiceRequest;
  const _TodayView({required this.focusRequest, this.voiceRequest});

  @override
  State<_TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<_TodayView> {
  DateTime _currentDay = dayStart(DateTime.now());
  final _inputFocus = FocusNode();
  final _textController = TextEditingController();

  // Composer state
  Activity? _selectedActivity;
  String? _draftEmoji;
  int? _selectedMeasureId;
  double _qty = 1.0;
  final _noteController = TextEditingController();
  bool _showOptions = false;

  /// "Yeni Olarak Ekle" seçildiyse benzer adlı bir aktiviteye bağlanmak yerine yazılan adla yenisi açılır.
  bool _forceNew = false;

  /// Yazılan metin sayaç komutu olarak okunurken kullanıcı "kayıt olarak ekle"yi seçtiyse true.
  bool _asEntry = false;

  /// Giriş kutusunda yapılacak modunun seçili olup olmadığı (Kayıt | Yapılacak).
  bool _isTodoMode = false;

  // Ölçü ve miktar metinden okunur; kullanıcı seçiciye dokunduysa oradaki değer geçerli olur.
  bool _measureTouched = false;
  bool _qtyTouched = false;

  List<ParsedItem>? _customItems;
  final _previewScrollController = ScrollController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    widget.focusRequest.addListener(_onFocusRequested);
    widget.voiceRequest?.addListener(_onVoiceRequested);
    store.todoCompletedNotifier.addListener(_onTodoCompleted);
    store.unmeasuredFixMessageNotifier.addListener(_onUnmeasuredFixMessage);
    if (store.unmeasuredFixMessageNotifier.value != null) {
      _onUnmeasuredFixMessage();
    }
    // Öneriler giriş kutusu odaklanınca da gösterilir.
    _inputFocus.addListener(_onFocusChanged);
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_textController.text.trim().isEmpty && _isTodoMode) {
      setState(() => _isTodoMode = false);
    }
    if (_customItems != null) {
      setState(() => _customItems = null);
    }
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onFocusRequested);
    widget.voiceRequest?.removeListener(_onVoiceRequested);
    store.todoCompletedNotifier.removeListener(_onTodoCompleted);
    store.unmeasuredFixMessageNotifier.removeListener(_onUnmeasuredFixMessage);
    _inputFocus.removeListener(_onFocusChanged);
    _textController.removeListener(_onTextChanged);
    _inputFocus.dispose();
    _textController.dispose();
    _noteController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  void _onTodoCompleted() {
    final title = store.todoCompletedNotifier.value;
    if (title != null && mounted) {
      final isTr = strings.value.isTr;
      final sm = ScaffoldMessenger.of(context);
      sm.hideCurrentSnackBar();
      sm.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(isTr ? '✓ Tamamlandı: $title' : '✓ Completed: $title'),
        ),
      );
    }
  }

  void _onUnmeasuredFixMessage() {
    final msg = store.unmeasuredFixMessageNotifier.value;
    if (msg != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final sm = ScaffoldMessenger.of(context);
          sm.hideCurrentSnackBar();
          sm.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(msg),
            ),
          );
          store.unmeasuredFixMessageNotifier.value = null;
        }
      });
    }
  }

  void _onVoiceRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openVoiceInput();
    });
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusRequested() {
    if (mounted) {
      setState(() => _currentDay = dayStart(DateTime.now()));
      _inputFocus.requestFocus();
    }
  }

  void _resetComposer() {
    _textController.clear();
    _noteController.clear();
    setState(() {
      _selectedActivity = null;
      _draftEmoji = null;
      _selectedMeasureId = null;
      _qty = 1.0;
      _showOptions = false;
      _forceNew = false;
      _asEntry = false;
      _isTodoMode = false;
      _measureTouched = false;
      _qtyTouched = false;
      _customItems = null;
    });
    _inputFocus.unfocus();
  }

  void _selectActivity(Activity a) {
    final st = store.stats[a.id];
    setState(() {
      _selectedActivity = a;
      _isTodoMode = false;
      _draftEmoji = a.emoji;
      _textController.text = a.name;
      _selectedMeasureId = st?.lastMeasureId;
      _qty = 1.0;
      _showOptions = true;
      _forceNew = false;
      _asEntry = false;
      _measureTouched = false;
      _qtyTouched = false;
      _customItems = null;
    });
  }

  /// Serbest metinden ayrıştırılan öğelerin güncel listesi.
  List<ParsedItem> _currentItems() {
    if (_customItems != null) return _customItems!;
    final text = _textController.text.trim();
    if (_selectedActivity != null || text.isEmpty) return const [];

    final multi = NaturalLanguageParser.parseMulti(
      text,
      activities: _forceNew ? const [] : store.activities.values.toList(),
      measures: store.measures,
      openTodos: store.todos,
      now: DateTime.now(),
      fallbackDay: _currentDay,
      defaultMeasureFor: store.defaultMeasureFor,
      predictCompletedTodos: store.predictCompletedTodos,
      forceTodo: _isTodoMode,
    );
    return multi.items;
  }

  /// Kutuya yazılanın gönder düğmesine basılınca neye dönüşeceği; aktivite listeden seçildiyse ya da kutu
  /// boşsa null. Önizleme satırı da kaydetme de bu planı kullanır: ekranda yazan ile yapılan aynıdır.
  _ComposerPlan? _plan() {
    if (_isTodoMode) return null;
    final text = _textController.text.trim();
    if (_selectedActivity != null || text.isEmpty) return null;

    final items = _currentItems();
    if (items.length != 1 || items.first is! EntryParsedItem) return null;
    final firstItem = items.first as EntryParsedItem;

    final activities = _forceNew ? const <Activity>[] : store.activities.values.toList();
    NlParseResult read({required bool commands}) => NaturalLanguageParser.parse(
          firstItem.rawText,
          activities: activities,
          measures: store.measures,
          allowCommands: commands,
          defaultMeasureFor: store.defaultMeasureFor,
        );
    final withCommands = read(commands: !_forceNew);
    final canBeCommand = withCommands.timerCommand != null;
    final parsed = canBeCommand && _asEntry ? read(commands: false) : withCommands;

    final hasExplicitAmount = parsed.hasExplicitQuantity || parsed.matchedMeasure != null;
    final existingAct = firstItem.activity ?? store.exactMatch(firstItem.activityName);
    final defMeasureId = (existingAct != null && hasExplicitAmount)
        ? store.defaultMeasureFor(existingAct.id)?.id
        : null;
    final effMeasureId = _measureTouched
        ? _selectedMeasureId
        : (parsed.matchedMeasure?.id ?? defMeasureId ?? _selectedMeasureId);

    return _ComposerPlan(
      parsed: parsed,
      existing: existingAct,
      measureId: effMeasureId,
      qty: _qtyTouched ? _qty : (parsed.quantity > 0 ? parsed.quantity : _qty),
      canBeCommand: canBeCommand,
    );
  }

  void _removeItem(int index) {
    setState(() {
      final items = List<ParsedItem>.from(_currentItems());
      if (index >= 0 && index < items.length) {
        items.removeAt(index);
        _customItems = items;
      }
    });
  }

  void _convertToTodo(int index) {
    setState(() {
      final items = List<ParsedItem>.from(_currentItems());
      if (index >= 0 && index < items.length) {
        final item = items[index];
        if (item is EntryParsedItem) {
          items[index] = item.toTodoItem();
          _customItems = items;
        }
      }
    });
  }

  Future<void> _pickDateTime(int index, DateTime current) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (!mounted) return;

    final h = pickedTime?.hour ?? current.hour;
    final m = pickedTime?.minute ?? current.minute;
    final newDt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, h, m);

    setState(() {
      final items = List<ParsedItem>.from(_currentItems());
      if (index >= 0 && index < items.length) {
        final item = items[index];
        if (item is EntryParsedItem) {
          items[index] = item.copyWith(
            at: newDt,
            hasExplicitDate: true,
            hasExplicitTime: true,
            isExplicitFuture: newDt.isAfter(DateTime.now()),
          );
          _customItems = items;
        }
      }
    });
  }

  Future<void> _pickTodoDate(int index, DateTime current) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    setState(() {
      final items = List<ParsedItem>.from(_currentItems());
      if (index >= 0 && index < items.length) {
        final item = items[index];
        if (item is TodoParsedItem) {
          items[index] = item.copyWith(dueDate: pickedDate);
          _customItems = items;
        }
      }
    });
  }

  String _formatTimeChip(DateTime dt, {required bool isTr}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = targetDay.difference(today).inDays;
    final timeStr = DateFormat('HH:mm').format(dt);

    if (diffDays == 0) {
      return timeStr;
    } else if (diffDays == -1) {
      return isTr ? 'Dün $timeStr' : 'Yesterday $timeStr';
    } else if (diffDays == -2) {
      return isTr ? 'Önceki gün $timeStr' : '2 days ago $timeStr';
    } else if (diffDays == 1) {
      return isTr ? 'Yarın $timeStr' : 'Tomorrow $timeStr';
    } else {
      final d = DateFormat('d MMM', isTr ? 'tr' : 'en').format(dt);
      return '$d $timeStr';
    }
  }

  String _formatDateChip(DateTime dt, {required bool isTr}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = targetDay.difference(today).inDays;

    if (diffDays == 0) {
      return isTr ? 'Bugün' : 'Today';
    } else if (diffDays == 1) {
      return isTr ? 'Yarın' : 'Tomorrow';
    } else if (diffDays == -1) {
      return isTr ? 'Dün' : 'Yesterday';
    } else {
      return DateFormat('d MMM', isTr ? 'tr' : 'en').format(dt);
    }
  }

  /// Metin hiçbir kayıtlı aktiviteye bağlanmasaydı açılacak aktivitenin adı ("Yeni Olarak Ekle" bunu açar).
  String _nameAsNew(String text) {
    return NaturalLanguageParser.cleanActivityName(text, allowCommands: false);
  }

  /// Metindeki fiilin bir fiil kökü üzerinden bu aktiviteye bağlanıp bağlanmadığını denetler.
  bool _isVerbMatchedTo(String text, Activity act) {
    final rawWords = text.trim().split(RegExp(r'\s+'));
    for (final raw in rawWords) {
      final norm = normalizeTr(raw).replaceAll(RegExp(r'[^\wçğıöşüÇĞİÖŞÜ]'), '').toLowerCase();
      final root = NaturalLanguageParser.verbRootFor(norm);
      if (root != null) {
        final an = normalizeTr(act.name).toLowerCase();
        if (an.startsWith(root) ||
            (root == 'yuru' && an.contains('yuru')) ||
            (root == 'kos' && an.contains('kos')) ||
            (root == 'uyu' && an.contains('uyku')) ||
            (root == 'oku' && (an.contains('kitap') || an.contains('oku')))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Önizleme satırının metni: "💧 Su: 2 Su bardağı · 400 ml eklenecek", "🎸 Gitar: kronometre başlayacak".
  String _planText(_ComposerPlan plan) {
    final s = strings.value;
    final act = plan.existing;
    final emoji = act?.emoji ?? _draftEmoji;
    final name = act?.name ?? '${plan.parsed.activityName} (${s.newActivityMark})';
    final who = emoji != null && emoji.isNotEmpty ? '$emoji $name' : name;

    final timer = plan.timer;
    if (timer != null) {
      if (act != null && store.getTimerForActivity(act.id) != null) {
        return s.isTr ? '$who: zaten bir sayaç çalışıyor' : '$who: a timer is already running';
      }
      final minutes = timer.targetMs ~/ 60000;
      final what = switch (timer.mode) {
        'pomodoro' => s.isTr ? '$minutes dk pomodoro başlayacak' : 'a $minutes min pomodoro will start',
        'countdown' => s.isTr ? '$minutes dk geri sayım başlayacak' : 'a $minutes min countdown will start',
        _ => s.isTr ? 'kronometre başlayacak' : 'a stopwatch will start',
      };
      return '$who: $what';
    }

    final hasAmountInText = plan.parsed.hasExplicitQuantity || plan.parsed.hasExplicitMeasure || _measureTouched || _qtyTouched;
    final amount = hasAmountInText
        ? store.amountDetail(plan.measureId, plan.qty, activityId: act?.id)
        : '';
    final verb = s.isTr ? 'eklenecek' : 'will be added';
    return amount.isEmpty ? '$who $verb' : '$who: $amount $verb';
  }

  /// Giriş kutusunda seçilen emojiyi aktiviteye işler. Aktivite metinden bulunduysa ve emoji
  /// seçilmediyse mevcut emojiye dokunulmaz.
  Future<void> _applyDraftEmoji(Activity act) async {
    final untouched = _selectedActivity == null && _draftEmoji == null;
    if (untouched || act.emoji == _draftEmoji) return;
    act.emoji = _draftEmoji;
    await store.updateActivity(act);
  }

  /// Gönder düğmesi ve klavyenin "bitti" tuşu.
  /// Metinde miktar/ölçü zaten varsa ("2 kahve", "500 ml su", "30 dk koşu") veya sayaç komutuysa
  /// ya da seçenekler paneli açıksa, çift onay istenmeden tek dokunuşla doğrudan kaydedilir.
  /// Miktar/ölçü belirtilmemişse önce seçenekler paneli açılarak kullanıcının seçmesi sağlanır.
  void _onSubmitPressed() {
    if (_isSubmitting) return;
    final items = _currentItems();
    if (_selectedActivity != null) {
      _submitEntry();
      return;
    }

    if (items.isEmpty) return;

    final allTodos = items.every((i) => i is TodoParsedItem);
    if (!allTodos && items.length == 1 && items.first is EntryParsedItem) {
      final entryItem = items.first as EntryParsedItem;
      if (!entryItem.isExplicitFuture) {
        final plan = _plan();
        final hasExplicitAmount = plan != null &&
            (plan.parsed.hasExplicitQuantity || plan.parsed.hasExplicitMeasure);
        if (!_showOptions && plan != null && plan.timer == null && !hasExplicitAmount) {
          setState(() => _showOptions = true);
          return;
        }
      }
    }

    _submitEntry();
  }

  Future<void> _submitEntry() async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    try {
      final s = strings.value;
      final items = _currentItems();
      if (items.isEmpty && _selectedActivity == null) return;

    // Tek seçili aktivite akışı (seçenekler panelinden tıklanmışsa)
    if (_selectedActivity != null) {
      final act = _selectedActivity!;
      await _applyDraftEmoji(act);
      final entryTime = sameDay(_currentDay, DateTime.now())
          ? DateTime.now()
          : DateTime(_currentDay.year, _currentDay.month, _currentDay.day, 12, 0);

      // Kural: Süreli aktivite çipine dokunulduğunda saatsiz süreli kayıt şimdi biter (başlangıç = şimdi - süre)
      final m = store.measureById(_selectedMeasureId) ?? store.defaultMeasureFor(act.id);
      final unitId = m?.unitId;
      final val = m != null ? m.amount * _qty : _qty;
      DateTime effectiveAt = entryTime;
      DateTime? effectiveEndAt;
      if ((unitId == 'dk' || unitId == 'sa' || unitId == 'sn') && val > 0) {
        final durSecs = (val * (unitId == 'sa' ? 3600 : (unitId == 'dk' ? 60 : 1))).round();
        effectiveEndAt = entryTime;
        effectiveAt = entryTime.subtract(Duration(seconds: durSecs));
      }

      final res = await store.addEntry(
        act.id,
        measureId: _selectedMeasureId,
        qty: _qty,
        at: effectiveAt,
        endAt: effectiveEndAt,
        note: _noteController.text,
      );

      if (mounted) {
        final actName = act.emoji != null ? '${act.emoji} ${act.name}' : act.name;
        final msg = '$actName ${s.isTr ? "eklendi" : "logged"}';
        showSnack(
          context,
          msg,
          achieved: res.achieved,
          exceeded: res.exceeded,
          undo: () => store.deleteEntry(res.entry),
        );
      }

      _resetComposer();
      return;
    }

    // Gelecek zaman kontrolü
    final hasUnconvertedFuture = items.any((i) => i is EntryParsedItem && i.isExplicitFuture);
    if (hasUnconvertedFuture) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isTr
                ? 'Gelecek zamanlı kayıtlar eklenemez. Lütfen "Yapılacak olarak ekle"ye dokunun.'
                : 'Future entries cannot be logged. Please tap "Add as to-do".',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Tek öğeli sayaç komutuysa sayaç başlar (kullanıcı kayıt olarak eklemeyi seçmediyse)
    if (!_asEntry && items.length == 1 && items.first is EntryParsedItem) {
      final item = items.first as EntryParsedItem;
      final plan = _plan();
      final command = plan?.timer ?? item.timerCommand;
      if (command != null) {
        final act = plan?.existing ?? await store.addActivity(item.activityName, emoji: _draftEmoji);
        await _applyDraftEmoji(act);
        await _startTimer(act, mode: command.mode, targetMs: command.targetMs, note: _noteController.text);
        _resetComposer();
        return;
      }
    }

    final batchRes = await store.saveParsedItems(
      items,
      note: _noteController.text,
      overrideMeasureId: _measureTouched && items.length == 1 ? _selectedMeasureId : null,
      hasMeasureOverride: _measureTouched && items.length == 1,
      overrideQty: _qtyTouched && items.length == 1 ? _qty : null,
      draftEmoji: _draftEmoji,
    );
    if (batchRes.entries.isEmpty && batchRes.todos.isEmpty) return;

    if (mounted) {
      final eCount = batchRes.entries.length;
      final tCount = batchRes.todos.length;
      String msg;
      if (eCount > 0 && tCount > 0) {
        msg = s.isTr
            ? '$eCount kayıt, $tCount yapılacak eklendi'
            : '$eCount ${eCount == 1 ? "entry" : "entries"}, $tCount ${tCount == 1 ? "to-do" : "to-dos"} added';
      } else if (eCount > 0) {
        if (eCount == 1) {
          final act = store.activities[batchRes.entries.first.activityId];
          final actName = act?.emoji != null ? '${act!.emoji} ${act.name}' : (act?.name ?? '');
          msg = '$actName ${s.isTr ? "eklendi" : "logged"}';
        } else {
          msg = s.isTr ? '$eCount kayıt eklendi' : '$eCount entries added';
        }
      } else {
        msg = s.isTr
            ? '$tCount yapılacak eklendi'
            : '$tCount ${tCount == 1 ? "to-do" : "to-dos"} added';
      }

      showSnack(
        context,
        msg,
        achieved: batchRes.achievedGoals,
        exceeded: batchRes.exceededGoals,
        undo: batchRes.undo,
      );
    }

    _resetComposer();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      } else {
        _isSubmitting = false;
      }
    }
  }

  Future<void> _openVoiceInput() async {
    final s = strings.value;
    bool voiceSubmitting = false;
    await showVoiceInputDialog(
      context,
      onConfirmed: (result) async {
        if (voiceSubmitting) return;
        voiceSubmitting = true;
        try {
          final act = result.matchedActivity ??
              store.exactMatch(result.activityName) ??
              await store.addActivity(result.activityName);

        final command = result.timerCommand;
        if (command != null) {
          await _startTimer(act, mode: command.mode, targetMs: command.targetMs);
          return;
        }

        final entryTime = sameDay(_currentDay, DateTime.now())
            ? DateTime.now()
            : DateTime(_currentDay.year, _currentDay.month, _currentDay.day, 12, 0);
        final res = await store.addEntry(
          act.id,
          measureId: result.matchedMeasure?.id,
          qty: result.quantity,
          at: entryTime,
        );
        if (mounted) {
          final mName = result.matchedMeasure?.name ?? '';
          final qtyStr = result.quantity == result.quantity.roundToDouble()
              ? result.quantity.toInt().toString()
              : result.quantity.toString();
          final actionWord = s.isTr ? 'eklendi' : 'added';
          final msg = '$qtyStr $mName ${act.name} $actionWord ✨'.trim();
          showSnack(
            context,
            msg,
            achieved: res.achieved,
            exceeded: res.exceeded,
            undo: () => store.deleteEntry(res.entry),
          );
        }
      } finally {
        voiceSubmitting = false;
      }
    },
      onComplexInput: (spokenText) {
        setState(() {
          _textController.text = spokenText;
          _showOptions = false;
        });
        _inputFocus.requestFocus();
      },
    );
  }

  Widget _buildMultiItemPreview(List<ParsedItem> items) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Scrollbar(
        controller: _previewScrollController,
        thumbVisibility: items.length > 2,
        child: ListView.separated(
          controller: _previewScrollController,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: items.length,
          separatorBuilder: (_, index) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          itemBuilder: (ctx, idx) {
            final item = items[idx];
            if (item is EntryParsedItem) {
              return _buildEntryItemRow(item, idx, scheme, s);
            } else if (item is TodoParsedItem) {
              return _buildTodoItemRow(item, idx, scheme, s);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildEntryItemRow(EntryParsedItem item, int idx, ColorScheme scheme, AppStrings s) {
    final act = item.activity;
    final isNew = act == null || item.isNewActivity;
    final actName = isNew ? '${item.activityName} (${s.newActivityMark})' : act.name;
    final effectiveMId = item.measure?.id ?? (act != null ? store.defaultMeasureFor(act.id)?.id : null);
    final amountStr = store.amountDetail(effectiveMId, item.quantity, activityId: act?.id);
    final isTr = s.isTr;

    Widget leadingWidget;
    if (isNew) {
      leadingWidget = Text(item.timerCommand != null ? '⏱️' : '📝', style: const TextStyle(fontSize: 16));
    } else {
      leadingWidget = ActivityAvatar(act.id, size: 20, activity: act);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leadingWidget,
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      actName,
                      style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.bold),
                    ),
                    if (amountStr.isNotEmpty)
                      Text(
                        amountStr,
                        style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                      ),
                    if (item.isExplicitFuture) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isTr ? 'Gelecek zaman' : 'Future time',
                          style: TextStyle(
                            fontSize: AppFont.micro,
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _convertToTodo(idx),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_task, size: 12, color: scheme.primary),
                              const SizedBox(width: 3),
                              Text(
                                isTr ? 'Yapılacak olarak ekle' : 'Add as to-do',
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (item.hasExplicitDate || item.hasExplicitTime || item.isRelative) ...[
                      InkWell(
                        onTap: () => _pickDateTime(idx, item.at),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: 12, color: scheme.primary),
                              const SizedBox(width: 3),
                              Text(
                                _formatTimeChip(item.at, isTr: isTr),
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => _removeItem(idx),
              ),
            ],
          ),
          for (final t in item.willCompleteTodos) ...[
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 12, color: scheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isTr
                          ? 'Bu kayıt "${t.title}" yapılacağını tamamlar'
                          : 'This entry completes "${t.title}"',
                      style: TextStyle(
                        fontSize: AppFont.micro,
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTodoItemRow(TodoParsedItem item, int idx, ColorScheme scheme, AppStrings s) {
    final isTr = s.isTr;
    final dateText = item.dueDate != null ? _formatDateChip(item.dueDate!, isTr: isTr) : (isTr ? 'Tarihsiz' : 'No date');
    final unitSymbol = item.suggestedUnit != null ? ' ${store.unit(item.suggestedUnit!).symbol}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.bold),
                ),
                InkWell(
                  onTap: () => _pickTodoDate(idx, item.dueDate ?? DateTime.now()),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: scheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          dateText,
                          style: TextStyle(fontSize: AppFont.micro, color: scheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                if (item.suggestedActivity != null)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${item.suggestedActivity!.emoji ?? ""} ${item.suggestedActivity!.name}${item.suggestedAmount != null ? " · ${fmtNum(item.suggestedAmount!)}$unitSymbol" : ""}'.trim(),
                      style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  )
                else if (item.suggestedAmount != null)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${fmtNum(item.suggestedAmount!)}$unitSymbol'.trim(),
                      style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => _removeItem(idx),
          ),
        ],
      ),
    );
  }

  /// [act] için zaten bir sayaç çalışıyorsa bunu bildirir ve true döner.
  bool _warnIfTiming(Activity act) {
    if (store.getTimerForActivity(act.id) == null) return false;
    final s = strings.value;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.isTr
              ? '"${act.name}" için zaten bir sayaç çalışıyor!'
              : 'A timer is already active for "${act.name}"!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  /// [act] için sayaç başlatır ve sonucu bildirir; aktivitenin zaten bir sayacı varsa yenisini açmaz.
  Future<void> _startTimer(Activity act, {required String mode, required int targetMs, String? note}) async {
    if (_warnIfTiming(act)) return;
    await store.startTimer(act.id, note: note, mode: mode, targetMs: targetMs);
    if (!mounted) return;

    final s = strings.value;
    final actName = act.emoji != null ? '${act.emoji} ${act.name}' : act.name;
    final modeStr = mode == 'pomodoro'
        ? 'Pomodoro'
        : (mode == 'countdown' ? (s.isTr ? 'Geri Sayım' : 'Countdown') : (s.isTr ? 'Kronometre' : 'Stopwatch'));
    final minutes = targetMs ~/ 60000;
    final what = minutes > 0 ? '$minutes ${s.isTr ? "dk" : "min"} $modeStr' : modeStr;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$actName · $what ${s.isTr ? "başlatıldı" : "started"}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startStopwatchFromComposer() async {
    final s = strings.value;
    final text = _textController.text.trim();
    Activity? act = _selectedActivity;
    String? newName;
    if (act == null && text.isNotEmpty) {
      final plan = _plan()!;
      act = plan.existing;
      if (act == null) newName = plan.parsed.activityName;
    } else if (act == null) {
      act = await showActivityPicker(
        context,
        title: s.isTr ? 'Sayaç Başlatmak İçin Seç' : 'Choose Activity for Timer',
      );
      if (act == null || !mounted) return;
    }

    if (act != null && _warnIfTiming(act)) {
      _resetComposer();
      return;
    }

    // Yeni aktivite ancak sayaç türü seçilince oluşturulur; pencere kapatılırsa geride boş aktivite kalmaz.
    final shown = act ?? Activity(id: 0, name: trCapitalize(newName!), emoji: _draftEmoji, createdAt: 0);
    final config = await showTimerModeDialog(context, shown);
    if (config == null || !mounted) return;

    act ??= await store.addActivity(newName!, emoji: _draftEmoji);
    await _applyDraftEmoji(act);
    await _startTimer(act, mode: config.mode, targetMs: config.targetMs, note: _noteController.text);
    _resetComposer();
  }

  Future<void> _startTimerForActivity(Activity act) async {
    if (_warnIfTiming(act)) return;
    final config = await showTimerModeDialog(context, act);
    if (config == null || !mounted) return;
    await _startTimer(act, mode: config.mode, targetMs: config.targetMs);
  }

  /// Giriş kutusu sayfanın altına sabitlenir. Seçenekler ve öneriler yukarı doğru açılır, yazı satırı
  /// en altta (klavyenin hemen üstünde) kalır. [maxHeight] aşılırsa içerik kendi içinde kayar.
  Widget _buildComposer(double maxHeight) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final q = _textController.text.trim();
    final suggestions = store.suggest(q, limit: 5);
    final showOptions = _showOptions || _selectedActivity != null;
    final showSuggestions = _selectedActivity == null && (q.isNotEmpty || _inputFocus.hasFocus);
    // Hiç aktivite yokken ne yazılabileceğini örnekler gösterir.
    final examples = showSuggestions && q.isEmpty && store.activities.isEmpty ? s.composerExamples : const <String>[];
    final items = _currentItems();
    final allTodos = items.isNotEmpty && items.every((i) => i is TodoParsedItem);
    final allEntries = _selectedActivity != null || (items.isNotEmpty && items.every((i) => i is EntryParsedItem));
    final isEntrySelected = allEntries || (items.isEmpty && !_isTodoMode);
    final isTodoSelected = allTodos || (items.isEmpty && _isTodoMode);
    final isSingleEntry = items.length == 1 && items.first is EntryParsedItem;
    final singleEntry = isSingleEntry ? (items.first as EntryParsedItem) : null;
    final plan = _plan();
    final startsTimer = plan?.timer != null;
    final hasText = q.isNotEmpty;
    final modeSelector = hasText
        ? _ComposerModeSelector(
            isEntrySelected: isEntrySelected,
            isTodoSelected: isTodoSelected,
            onChanged: (todo) {
              setState(() {
                _customItems = null;
                if (_selectedActivity != null) {
                  _textController.text = _selectedActivity!.name;
                  _selectedActivity = null;
                }
                if (todo) {
                  _isTodoMode = true;
                } else {
                  _isTodoMode = false;
                  final currentText = _textController.text;
                  final stripped = NaturalLanguageParser.stripTodoMarker(currentText);
                  if (stripped != currentText) {
                    _textController.text = stripped;
                  }
                }
                _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
              });
            },
          )
        : null;
    final matchedAct = plan?.existing;
    // "Yeni Olarak Ekle": metin kayıtlı bir aktiviteye bağlanmışken (örn: "Kitap okuma"),
    // kullanıcının yazdığı farklı adla (örn: "Kitap") yeni bir aktivite açma seçeneği.
    // Metin zaten kendi adına eşlendiyse ("dun gece 500 ml su" -> Su), fiil kökünden geldiyse
    // ("20 dk yurudum" -> Yürüyüş) veya eşleşen yoksa çıkmaz.
    String? newName;
    if (matchedAct != null && !startsTimer && q.isNotEmpty) {
      final candidate = _nameAsNew(q);
      final isSameAct = normalizeTr(candidate) == normalizeTr(matchedAct.name);
      final isVerbMatched = _isVerbMatchedTo(q, matchedAct);
      if (candidate.isNotEmpty &&
          !isSameAct &&
          !isVerbMatched &&
          store.exactMatch(candidate) == null) {
        newName = candidate;
      }
    }
    final canAddNew = newName != null && !suggestions.any((a) => normalizeTr(a.name) == normalizeTr(newName!));
    // Seçici, kaydedilecek olanı gösterir: metinden okunan ölçü ve miktar ya da kullanıcının değiştirdiği.
    final shownMeasureId = plan?.measureId ?? _selectedMeasureId;
    final shownQty = plan?.qty ?? _qty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Options expanded (Measure & Quantity)
              if (showOptions) ...[
                Row(
                  children: [
                    // Emoji button
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final chosen = await showEmojiPicker(context, currentEmoji: _draftEmoji);
                        if (chosen != null) setState(() => _draftEmoji = chosen);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _draftEmoji?.isNotEmpty == true ? _draftEmoji! : '✨',
                          style: const TextStyle(fontSize: AppFont.title),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        startsTimer ? s.timerNoteTitle : s.selectMeasure,
                        style: TextStyle(
                          fontSize: AppFont.small,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    if (_selectedActivity != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: s.isTr ? 'Aktiviteyi düzenle' : 'Edit activity',
                        onPressed: () => showActivityEditDialog(context, _selectedActivity!),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Sayaç komutunda ölçü ve miktar yoktur.
                if (!startsTimer) ...[
                  MeasureQtyPicker(
                    activityId: _selectedActivity?.id ?? plan?.existing?.id,
                    measureId: shownMeasureId,
                    qty: shownQty,
                    onChanged: (mId, qVal) {
                      setState(() {
                        if (mId != shownMeasureId) _measureTouched = true;
                        if (qVal != shownQty) _qtyTouched = true;
                        _selectedMeasureId = mId;
                        _qty = qVal;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    hintText: s.noteHint,
                    isDense: true,
                    prefixIcon: const Icon(Icons.notes, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const Divider(height: 20),
              ],

              // Suggestions while typing
              if (showSuggestions && (suggestions.isNotEmpty || canAddNew || examples.isNotEmpty)) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final example in examples)
                      ActionChip(
                        avatar: const Icon(Icons.lightbulb_outline, size: 16),
                        label: Text(example),
                        onPressed: () {
                          _textController.text = example;
                          _textController.selection = TextSelection.collapsed(offset: example.length);
                          setState(() {});
                        },
                      ),
                    for (final a in suggestions)
                      GestureDetector(
                        onLongPress: () async {
                          HapticFeedback.mediumImpact();
                          final msg = await store.repeatLastEntry(a.id);
                          if (msg != null && mounted) {
                            showSnack(context, msg);
                          }
                        },
                        child: ActionChip(
                          tooltip: s.isTr
                              ? 'Dokun: seç · Basılı tut: son kaydı tekrarla'
                              : 'Tap: select · Long press: repeat last entry',
                          avatar: a.emoji != null ? Text(a.emoji!, style: const TextStyle(fontSize: AppFont.subtitle)) : null,
                          label: Text(a.name),
                          onPressed: () => _selectActivity(a),
                        ),
                      ),
                    if (canAddNew)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text('${s.addNewAction}: "$newName"'),
                        onPressed: () {
                          setState(() {
                            _showOptions = true;
                            _forceNew = true;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              if (modeSelector != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: modeSelector,
                  ),
                ),
              ],

              if (items.length > 1 || (items.isNotEmpty && items.first is TodoParsedItem)) ...[
                _buildMultiItemPreview(items),
              ] else if (plan != null) ...[
                if (singleEntry != null && singleEntry.isExplicitFuture) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 6),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 6),
                            Text(
                              s.isTr ? 'Gelecek zaman' : 'Future time',
                              style: TextStyle(
                                fontSize: AppFont.small,
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add_task, size: 14),
                          label: Text(s.isTr ? 'Yapılacak olarak ekle' : 'Add as to-do'),
                          onPressed: () => _convertToTodo(0),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _ComposerPreview(
                    startsTimer: startsTimer,
                    text: _planText(plan),
                    otherLabel: plan.canBeCommand ? (startsTimer ? s.previewAsEntry : s.previewAsTimer) : null,
                    onOther: () => setState(() => _asEntry = !_asEntry),
                    onToggleOptions: () => setState(() => _showOptions = !_showOptions),
                    optionsOpen: _showOptions,
                    timeChip: singleEntry != null &&
                            (singleEntry.hasExplicitDate || singleEntry.hasExplicitTime || singleEntry.isRelative)
                        ? InkWell(
                            onTap: () => _pickDateTime(0, singleEntry.at),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    _formatTimeChip(singleEntry.at, isTr: s.isTr),
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                  Builder(builder: (c) {
                    final willCompletes = singleEntry?.willCompleteTodos ?? const [];
                    if (willCompletes.isEmpty || startsTimer) return const SizedBox.shrink();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final willComplete in willCompletes)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 4),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, size: 14, color: Theme.of(c).colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.isTr
                                        ? 'Bu kayıt "${willComplete.title}" yapılacağını tamamlar'
                                        : 'This entry completes "${willComplete.title}"',
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      color: Theme.of(c).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ],

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _inputFocus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: s.composerHint,
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        suffixIcon: _textController.text.isNotEmpty || _selectedActivity != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: s.isTr ? 'Temizle' : 'Clear',
                                onPressed: _resetComposer,
                              )
                            : null,
                      ),
                      onChanged: (text) {
                        setState(() {
                          _forceNew = false;
                          _customItems = null;
                          if (text.trim().isEmpty) {
                            _asEntry = false;
                            _isTodoMode = false;
                          }
                          if (_selectedActivity != null && _selectedActivity!.name != text) {
                            _selectedActivity = null;
                          }
                        });
                      },
                      onSubmitted: (_) {
                        if (!_isSubmitting) _onSubmitPressed();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: s.isTr ? 'Sesli / Akıllı Giriş' : 'Voice / Smart Input',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.mic, size: 20),
                    onPressed: _openVoiceInput,
                  ),
                  IconButton.filledTonal(
                    tooltip: s.startStopwatch,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.timer_outlined, size: 20),
                    onPressed: _startStopwatchFromComposer,
                  ),
                  // Düğme ne yapacaksa onu gösterir: kayıt ekler ya da sayaç başlatır.
                  IconButton.filled(
                    key: const Key('composer-submit'),
                    tooltip: allTodos
                        ? (s.isTr ? 'Yapılacak ekle' : 'Add to-do')
                        : (startsTimer ? s.startTimerAction : s.logButton),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      allTodos
                          ? Icons.checklist_rounded
                          : (startsTimer ? Icons.play_arrow_rounded : Icons.check_rounded),
                      size: 22,
                    ),
                    onPressed: ((q.isNotEmpty || _selectedActivity != null) && !_isSubmitting) ? _onSubmitPressed : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final isToday = sameDay(_currentDay, DateTime.now());
        final daySummary = store.getDaySummary(_currentDay);
        final subtitleParts = <String>[
          fmtDateShort(_currentDay, isTr: s.isTr),
          if (daySummary.count > 0) '${daySummary.count} ${s.entriesCountSuffix}',
          if (daySummary.totalTimeMinutes > 0) fmtAmount(daySummary.totalTimeMinutes, 'time'),
        ];
        return LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    tooltip: s.isTr ? 'Önceki gün' : 'Previous day',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    onPressed: () => setState(() => _currentDay = subDays(_currentDay, 1)),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _currentDay,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _currentDay = dayStart(picked));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    fmtDayTitle(_currentDay, isTr: s.isTr),
                                    style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                            Text(
                              subtitleParts.join(' · '),
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    tooltip: s.isTr ? 'Sonraki gün' : 'Next day',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    onPressed: isToday ? null : () => setState(() => _currentDay = addDays(_currentDay, 1)),
                  ),
                ],
              ),
              actions: [
                if (!isToday)
                  IconButton(
                    icon: const Icon(Icons.today_rounded),
                    tooltip: s.isTr ? 'Bugüne dön' : 'Go to today',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => setState(() => _currentDay = dayStart(DateTime.now())),
                  ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: s.isTr ? 'Kayıt & Not Ara' : 'Search Entries & Notes',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () async {
                    final res = await showSearch(
                      context: context,
                      delegate: TakipSearchDelegate(store: store),
                    );
                    if (!context.mounted) return;
                    if (res is DateTime) {
                      setState(() => _currentDay = dayStart(res));
                    } else if (res is Activity) {
                      _selectActivity(res);
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (store.activeTimers.isNotEmpty)
                    ActiveTimersSection(timers: store.activeTimers),
                  TodaySummaryCard(
                    currentDay: _currentDay,
                    onStartTimer: _startTimerForActivity,
                  ),
                  const TodayTodosCard(),
                  TodayHealthPanel(
                    currentDay: _currentDay,
                    onRefresh: () => setState(() {}),
                  ),
                  TodayRoutinesPanel(currentDay: _currentDay),
                  TodayQuickShortcuts(
                    currentDay: _currentDay,
                    onStartTimer: _startTimerForActivity,
                  ),
                  if (store.activeRoadmaps.isNotEmpty)
                    TodayRoadmapPanel(
                      currentDay: _currentDay,
                      onStartTimer: _startTimerForActivity,
                    ),
                  TodayTimeline(
                    currentDay: _currentDay,
                    onStartTimer: _startTimerForActivity,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // Giriş kutusu kaydırılan içeriğin dışında, altta sabit durur; sayaçlar ve paneller ne kadar
            // uzarsa uzasın yeni kayıt tek dokunuş uzaktadır.
            bottomNavigationBar: _buildComposer(max(140.0, (constraints.maxHeight - kToolbarHeight) * 0.72)),
          ),
        );
      },
    );
  }
}
