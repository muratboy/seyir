import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/todo_parser.dart';
import '../app_font.dart';
import '../common.dart';

/// Hızlı Todo ekleme bottom sheet'i. Otomatik odaklanan tek alan, yazarken tarih/aktivite çıkarma,
/// hızlı çipler ve art arda ekleme desteği.
class TodoQuickAddSheet extends StatefulWidget {
  const TodoQuickAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TodoQuickAddSheet(),
    );
  }

  @override
  State<TodoQuickAddSheet> createState() => _TodoQuickAddSheetState();
}

class _TodoQuickAddSheetState extends State<TodoQuickAddSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  DateTime? _selectedDate;
  Activity? _linkedActivity;
  double? _targetAmount;
  String? _targetUnit;

  bool _manualDateOverridden = false;
  bool _manualActivityOverridden = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;

    final parsed = TodoInputParser.parse(
      text,
      activities: store.activities.values.where((a) => !a.isArchived).toList(),
      measures: store.measures,
    );

    setState(() {
      if (!_manualDateOverridden && parsed.date != null) {
        _selectedDate = parsed.date;
      }
      if (!_manualActivityOverridden && parsed.suggestedActivity != null) {
        _linkedActivity = parsed.suggestedActivity;
        _targetAmount = parsed.suggestedAmount;
        _targetUnit = parsed.suggestedUnit;
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _manualDateOverridden = true;
      });
    }
  }

  Future<void> _pickActivity() async {
    final s = strings.value;
    final act = await showActivityPicker(
      context,
      title: s.isTr ? 'Aktivite Bağla' : 'Link Activity',
    );
    if (act != null) {
      setState(() {
        _linkedActivity = act;
        _manualActivityOverridden = true;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final rawText = _controller.text.trim();
    if (rawText.isEmpty) return;
    _isSaving = true;
    try {
      // Başlıktan tarih kelimesini ayıkla
    final parsed = TodoInputParser.parse(
      rawText,
      activities: store.activities.values.where((a) => !a.isArchived).toList(),
      measures: store.measures,
    );
    final title = parsed.cleanTitle.isNotEmpty ? parsed.cleanTitle : rawText;

    final dueDateStr = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : null;

    final todo = Todo(
      id: 0,
      title: title,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      dueDate: dueDateStr,
      targetAmount: _targetAmount,
      targetUnit: _targetUnit,
    );

    await store.createTodo(
      todo,
      activityIds: _linkedActivity != null ? [_linkedActivity!.id] : null,
    );

    // Alanı temizle ve açık bırak (art arda ekleme)
    _controller.clear();
    setState(() {
      _selectedDate = null;
      _linkedActivity = null;
      _targetAmount = null;
      _targetUnit = null;
      _manualDateOverridden = false;
      _manualActivityOverridden = false;
    });

    if (mounted) {
      _focusNode.requestFocus();
      final s = strings.value;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            s.isTr ? '✓ Eklendi: $title' : '✓ Added: $title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      } else {
        _isSaving = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tutamaç
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Başlık satırı
          Row(
            children: [
              Text(
                s.isTr ? 'Yeni Yapılacak' : 'New To-do',
                style: const TextStyle(
                  fontSize: AppFont.subtitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // Metin Giriş Alanı
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: s.isTr ? 'Ne yapılacak? (örn: 30 dk yürü yarın)' : 'What needs to be done? (e.g. 30 min walk tomorrow)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_upward_rounded),
                onPressed: _isSaving ? null : _save,
              ),
            ),
            onSubmitted: (_) {
              if (!_isSaving) _save();
            },
          ),

          const SizedBox(height: 10),

          // Akıllı ve Hızlı Çipler (Wrap ile sağdan taşma önlenir, eşleşen çip seçili görünür)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 1. Bugün çipi
              FilterChip(
                avatar: const Icon(Icons.today_rounded, size: 16),
                label: Text(s.isTr ? 'Bugün' : 'Today'),
                selected: _selectedDate != null && sameDay(_selectedDate!, today),
                onSelected: (sel) {
                  setState(() {
                    _selectedDate = sel ? today : null;
                    _manualDateOverridden = true;
                  });
                },
              ),

              // 2. Yarın çipi
              FilterChip(
                avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                label: Text(s.isTr ? 'Yarın' : 'Tomorrow'),
                selected: _selectedDate != null && sameDay(_selectedDate!, today.add(const Duration(days: 1))),
                onSelected: (sel) {
                  setState(() {
                    _selectedDate = sel ? today.add(const Duration(days: 1)) : null;
                    _manualDateOverridden = true;
                  });
                },
              ),

              // 3. Hafta sonu çipi
              Builder(builder: (c) {
                final wd = today.weekday;
                final offset = (wd == 6 || wd == 7) ? 0 : (6 - wd);
                final weekendDate = today.add(Duration(days: offset));
                final isWeekendSel = _selectedDate != null && sameDay(_selectedDate!, weekendDate);
                return FilterChip(
                  avatar: const Icon(Icons.weekend_outlined, size: 16),
                  label: Text(s.isTr ? 'Hafta sonu' : 'Weekend'),
                  selected: isWeekendSel,
                  onSelected: (sel) {
                    setState(() {
                      _selectedDate = sel ? weekendDate : null;
                      _manualDateOverridden = true;
                    });
                  },
                );
              }),

              // 4. Özel tarih çipi veya Tarih... seçici
              Builder(builder: (c) {
                final isToday = _selectedDate != null && sameDay(_selectedDate!, today);
                final isTomorrow = _selectedDate != null && sameDay(_selectedDate!, today.add(const Duration(days: 1)));
                final wd = today.weekday;
                final offset = (wd == 6 || wd == 7) ? 0 : (6 - wd);
                final isWeekend = _selectedDate != null && sameDay(_selectedDate!, today.add(Duration(days: offset)));
                final isCustomDate = _selectedDate != null && !isToday && !isTomorrow && !isWeekend;

                if (isCustomDate) {
                  return InputChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(DateFormat.MMMd(s.isTr ? 'tr_TR' : 'en_US').format(_selectedDate!)),
                    selected: true,
                    onPressed: _pickCustomDate,
                    onDeleted: () {
                      setState(() {
                        _selectedDate = null;
                        _manualDateOverridden = true;
                      });
                    },
                  );
                }

                return ActionChip(
                  avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                  label: Text(s.isTr ? 'Tarih…' : 'Date…'),
                  onPressed: _pickCustomDate,
                );
              }),

              // 5. Bağlı aktivite çipi veya Aktivite bağla butonu
              if (_linkedActivity != null)
                InputChip(
                  avatar: Text(_linkedActivity!.emoji ?? '🔹'),
                  label: Text(
                    '${_linkedActivity!.name}${_targetAmount != null ? " · ${fmtNum(_targetAmount!)}${_targetUnit != null ? " $_targetUnit" : ""}" : ""}',
                  ),
                  selected: true,
                  onPressed: _pickActivity,
                  onDeleted: () {
                    setState(() {
                      _linkedActivity = null;
                      _targetAmount = null;
                      _targetUnit = null;
                      _manualActivityOverridden = true;
                    });
                  },
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.link_rounded, size: 16),
                  label: Text(s.isTr ? 'Aktivite bağla' : 'Link activity'),
                  onPressed: _pickActivity,
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Ekle Düğmesi
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add),
            label: Text(s.isTr ? 'Ekle' : 'Add'),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
    );
  }
}
