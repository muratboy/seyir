import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import '../services/nl_parser.dart';
import 'common.dart';
import 'components/active_timer_card.dart';
import 'components/today_day_summary.dart';
import 'components/today_health_panel.dart';
import 'components/today_quick_shortcuts.dart';
import 'components/today_roadmap_panel.dart';
import 'components/today_timeline.dart';
import 'voice_dialog.dart';
import 'app_font.dart';

class TodayPage extends StatelessWidget {
  final ValueNotifier<int> focusRequest;
  const TodayPage({super.key, required this.focusRequest});

  @override
  Widget build(BuildContext context) {
    // Sayfanın kendi bildirim alanı vardır: snackbar'lar alta sabitlenmiş giriş kutusunun üstünde belirir,
    // onu örtmez.
    return ScaffoldMessenger(child: _TodayView(focusRequest: focusRequest));
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

/// Gönder düğmesine basılınca ne olacağını söyleyen satır. Uygulama yazılanı sessizce yorumlamaz: sayaç
/// mı başlayacak, hangi aktiviteye ne kadar eklenecek, önce burada görünür. Metin iki türlü okunabiliyorsa
/// [otherLabel] öbür okumaya geçirir.
class _ComposerPreview extends StatelessWidget {
  final bool startsTimer;
  final String text;
  final String? otherLabel;
  final VoidCallback onOther;

  const _ComposerPreview({
    required this.startsTimer,
    required this.text,
    required this.otherLabel,
    required this.onOther,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                text,
                key: const Key('composer-preview'),
                style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
              ),
            ),
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
  const _TodayView({required this.focusRequest});

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

  // Ölçü ve miktar metinden okunur; kullanıcı seçiciye dokunduysa oradaki değer geçerli olur.
  bool _measureTouched = false;
  bool _qtyTouched = false;

  @override
  void initState() {
    super.initState();
    widget.focusRequest.addListener(_onFocusRequested);
    // Öneriler giriş kutusu odaklanınca da gösterilir.
    _inputFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onFocusRequested);
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.dispose();
    _textController.dispose();
    _noteController.dispose();
    super.dispose();
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
      _measureTouched = false;
      _qtyTouched = false;
    });
    _inputFocus.unfocus();
  }

  void _selectActivity(Activity a) {
    final st = store.stats[a.id];
    setState(() {
      _selectedActivity = a;
      _draftEmoji = a.emoji;
      _textController.text = a.name;
      _selectedMeasureId = st?.lastMeasureId;
      _qty = 1.0;
      _showOptions = true;
      _forceNew = false;
      _asEntry = false;
      _measureTouched = false;
      _qtyTouched = false;
    });
  }

  /// Kutuya yazılanın gönder düğmesine basılınca neye dönüşeceği; aktivite listeden seçildiyse ya da kutu
  /// boşsa null. Önizleme satırı da kaydetme de bu planı kullanır: ekranda yazan ile yapılan aynıdır.
  _ComposerPlan? _plan() {
    final text = _textController.text.trim();
    if (_selectedActivity != null || text.isEmpty) return null;

    // "Yeni Olarak Ekle" bir kayıt isteğidir: benzer adlı aktiviteye bağlanılmaz, komut da aranmaz.
    final activities = _forceNew ? const <Activity>[] : store.activities.values.toList();
    NlParseResult read({required bool commands}) => NaturalLanguageParser.parse(
          text,
          activities: activities,
          measures: store.measures,
          allowCommands: commands,
        );
    final withCommands = read(commands: !_forceNew);
    final canBeCommand = withCommands.timerCommand != null;
    final parsed = canBeCommand && _asEntry ? read(commands: false) : withCommands;

    return _ComposerPlan(
      parsed: parsed,
      existing: parsed.matchedActivity ?? store.exactMatch(parsed.activityName),
      measureId: _measureTouched ? _selectedMeasureId : (parsed.matchedMeasure?.id ?? _selectedMeasureId),
      qty: _qtyTouched ? _qty : (parsed.quantity > 0 ? parsed.quantity : _qty),
      canBeCommand: canBeCommand,
    );
  }

  /// Metin hiçbir kayıtlı aktiviteye bağlanmasaydı açılacak aktivitenin adı ("Yeni Olarak Ekle" bunu açar).
  String _nameAsNew(String text) => NaturalLanguageParser.parse(
        text,
        activities: const [],
        measures: store.measures,
        allowCommands: false,
      ).activityName;

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

    final amount = store.amountDetail(plan.measureId, plan.qty);
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

  /// Gönder düğmesi ve klavyenin "bitti" tuşu. Yazılan bir kayıtsa önce ölçü ve miktar seçenekleri açılır;
  /// sayaç komutunda seçilecek bir şey yoktur, önizleme ne olacağını zaten söylemiştir.
  void _onSubmitPressed() {
    final plan = _plan();
    if (!_showOptions && plan != null && plan.timer == null) {
      setState(() => _showOptions = true);
    } else {
      _submitEntry();
    }
  }

  Future<void> _submitEntry() async {
    final s = strings.value;
    final plan = _plan();
    if (plan == null && _selectedActivity == null) return;

    Activity act;
    double finalQty = _qty;
    int? finalMeasureId = _selectedMeasureId;

    if (plan == null) {
      act = _selectedActivity!;
      await _applyDraftEmoji(act);
    } else {
      act = plan.existing ?? await store.addActivity(plan.parsed.activityName, emoji: _draftEmoji);
      await _applyDraftEmoji(act);

      // "kronometre", "pomodoro" ya da "geri sayım" yazıldıysa kayıt eklemek yerine sayaç başlar
      final command = plan.timer;
      if (command != null) {
        await _startTimer(act, mode: command.mode, targetMs: command.targetMs, note: _noteController.text);
        _resetComposer();
        return;
      }

      finalMeasureId = plan.measureId;
      finalQty = plan.qty;
    }

    final entryTime = sameDay(_currentDay, DateTime.now())
        ? DateTime.now()
        : DateTime(_currentDay.year, _currentDay.month, _currentDay.day, 12, 0);

    final res = await store.addEntry(
      act.id,
      measureId: finalMeasureId,
      qty: finalQty,
      at: entryTime,
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
  }

  Future<void> _openVoiceInput() async {
    final s = strings.value;
    await showVoiceInputDialog(
      context,
      onConfirmed: (result) async {
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
      },
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
    final plan = _plan();
    final startsTimer = plan?.timer != null;
    // "Yeni Olarak Ekle": metin kayıtlı bir aktiviteye kayıt olarak bağlanacakken, yazılan adla yenisini açma
    // seçeneği. Zaten yeni bir aktivite açılacaksa bunu önizleme söyler; sayaç komutunda ise önce "kayıt
    // olarak ekle" seçilir, aynı anda üç ayrı okuma sunulmaz.
    final newName = plan?.existing == null || startsTimer ? null : _nameAsNew(q);
    final canAddNew = newName != null && store.exactMatch(newName) == null;
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

              if (plan != null)
                _ComposerPreview(
                  startsTimer: startsTimer,
                  text: _planText(plan),
                  otherLabel: plan.canBeCommand ? (startsTimer ? s.previewAsEntry : s.previewAsTimer) : null,
                  onOther: () => setState(() => _asEntry = !_asEntry),
                ),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _inputFocus,
                      textCapitalization: TextCapitalization.sentences,
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
                          if (text.trim().isEmpty) _asEntry = false;
                          if (_selectedActivity != null && _selectedActivity!.name != text) {
                            _selectedActivity = null;
                          }
                        });
                      },
                      onSubmitted: (_) => _onSubmitPressed(),
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
                    tooltip: startsTimer ? s.startTimerAction : s.logButton,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(startsTimer ? Icons.play_arrow_rounded : Icons.check_rounded, size: 22),
                    onPressed: (q.isNotEmpty || _selectedActivity != null) ? _onSubmitPressed : null,
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
        return LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 4,
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
                  Flexible(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _currentDay,
                          firstDate: DateTime(2020),
                          lastDate: addDays(DateTime.now(), 365),
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
                              fmtDateShort(_currentDay, isTr: s.isTr),
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
                    onPressed: () => setState(() => _currentDay = addDays(_currentDay, 1)),
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
                  tooltip: s.isTr ? 'Aktivite Ara' : 'Search Activity',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () async {
                    final a = await showActivityPicker(context);
                    if (a != null) _selectActivity(a);
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
                  TodayDaySummary(currentDay: _currentDay),
                  TodayHealthPanel(
                    currentDay: _currentDay,
                    onRefresh: () => setState(() {}),
                  ),
                  TodayQuickShortcuts(onStartTimer: _startTimerForActivity),
                  if (store.activeRoadmaps.isNotEmpty)
                    TodayRoadmapPanel(onStartTimer: _startTimerForActivity),
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
