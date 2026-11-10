import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common_widgets.dart';
import '../../app/theme/app_theme.dart';

class ReadingScreen extends ConsumerWidget {
  const ReadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionHeader(
              title: 'Library', subtitle: 'Graded passages and articles'),
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No reading material yet',
            message:
                'Content import and reading engine arrive in a later phase. You can still track study time from Learn.',
            action: OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back to Learn'),
            ),
          ),
          const SizedBox(height: 16),
          LexiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Continue reading',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text('No active passage. Coming in Phase 2+.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
