import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/content/grammar_curriculum.dart';
import '../../../core/services/providers.dart';
import '../../../core/widgets/common_widgets.dart';

class GrammarStudioScreen extends ConsumerStatefulWidget {
  const GrammarStudioScreen({super.key});

  @override
  ConsumerState<GrammarStudioScreen> createState() =>
      _GrammarStudioScreenState();
}

class _GrammarStudioScreenState extends ConsumerState<GrammarStudioScreen> {
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    await GrammarCurriculum.seedIfEmpty(db);
    final rows = await db.getGrammarLessons();
    if (mounted)
      setState(() {
        _lessons = rows;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'All'
        ? _lessons
        : _lessons.where((l) => l['cefr_level'] == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Grammar Studio')),
      body: _loading
          ? const LoadingView()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    children: ['All', 'B1', 'B2'].map((f) {
                      return ChoiceChip(
                        label: Text(f),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final l = filtered[i];
                      final done = (l['completed'] as int?) == 1;
                      return LexiCard(
                        onTap: () =>
                            context.push('/learn/grammar/lesson/${l['id']}'),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                    (done ? AppColors.teal : AppColors.violet)
                                        .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                  done ? Icons.check : Icons.menu_book_outlined,
                                  color:
                                      done ? AppColors.teal : AppColors.violet),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${l['title']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  Text('${l['cefr_level']} · ${l['objective']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
