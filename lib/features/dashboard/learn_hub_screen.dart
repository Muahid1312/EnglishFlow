import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';
import 'dashboard_provider.dart';

class LearnHubScreen extends ConsumerWidget {
  const LearnHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(studySessionServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (session.hasActive) ...[
            LexiCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active session',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${session.active!.module} · ${_formatDuration(session.active!.elapsedSeconds)}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppColors.violet),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (session.isRunning)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                ref.read(studySessionServiceProvider).pause(),
                            icon: const Icon(Icons.pause),
                            label: const Text('Pause'),
                          ),
                        )
                      else
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                ref.read(studySessionServiceProvider).resume(),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Resume'),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(studySessionServiceProvider)
                                .finish();
                            ref.invalidate(dashboardProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Session saved')),
                              );
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Finish'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          SectionHeader(title: 'Modules'),
          ModuleTile(
            icon: Icons.menu_book_outlined,
            title: 'Reading',
            subtitle: 'Passages, comprehension & library',
            onTap: () => context.push('/learn/reading'),
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.style_outlined,
            title: 'Vocabulary',
            subtitle: 'Word bank & reviews',
            onTap: () => context.push('/learn/vocabulary'),
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.headphones_outlined,
            title: 'Listening & Speaking',
            subtitle: 'Audio lessons and practice',
            onTap: () => context.push('/learn/listening'),
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.edit_note_outlined,
            title: 'Grammar & Writing',
            subtitle: 'Exercises and journal',
            onTap: () => context.push('/learn/grammar'),
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.library_books_outlined,
            title: 'Books',
            subtitle: 'Courses and graded readers',
            onTap: () => context.push('/learn/books'),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'Start timed session'),
          Text(
            'Start a session to count minutes toward your daily goal. Time pauses when the app is backgrounded.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _SessionChip(label: 'Reading', module: 'reading'),
              _SessionChip(label: 'Vocabulary', module: 'vocabulary'),
              _SessionChip(label: 'Listening', module: 'listening_speaking'),
              _SessionChip(label: 'Grammar', module: 'grammar_writing'),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _SessionChip extends ConsumerWidget {
  final String label;
  final String module;

  const _SessionChip({required this.label, required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      avatar: const Icon(Icons.timer_outlined, size: 18),
      label: Text(label),
      onPressed: () async {
        await ref.read(studySessionServiceProvider).start(module);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Started $label session')),
          );
        }
      },
    );
  }
}
