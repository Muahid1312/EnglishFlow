import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';
import '../../app/theme/app_theme.dart';

class VocabularyScreen extends ConsumerWidget {
  const VocabularyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vocabulary')),
      body: FutureBuilder(
        future: Future.wait([db.getSavedWordCount(), db.getDueReviewCount()]),
        builder: (context, snap) {
          final words = snap.hasData ? snap.data![0] as int : 0;
          final due = snap.hasData ? snap.data![1] as int : 0;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: LexiCard(
                      child: Column(
                        children: [
                          Text('$words',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: AppColors.violet)),
                          const SizedBox(height: 4),
                          Text('Saved words',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LexiCard(
                      child: Column(
                        children: [
                          Text('$due',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: AppColors.teal)),
                          const SizedBox(height: 4),
                          Text('Due reviews',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionHeader(title: 'Review queue'),
              if (due == 0)
                EmptyState(
                  icon: Icons.style_outlined,
                  title: 'No reviews due',
                  message:
                      'Save words while reading (Phase 2) or start a vocabulary study session from Learn.',
                )
              else
                ModuleTile(
                  icon: Icons.replay,
                  title: 'Start review',
                  subtitle: '$due cards ready',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Full spaced-repetition engine arrives in a later phase.')),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
