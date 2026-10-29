import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/l10n.dart';
import 'app_font.dart';
import 'tabs/todos_tab.dart';

/// Tüm Yapılacaklar sayfası.
class TodosPage extends StatelessWidget {
  const TodosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              s.isTr ? 'Yapılacaklar' : 'To-dos',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.title),
            ),
          ),
          body: const TodosView(showFab: true),
        );
      },
    );
  }
}
