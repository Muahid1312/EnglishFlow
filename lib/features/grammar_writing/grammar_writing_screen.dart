import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';

class GrammarWritingScreen extends ConsumerWidget {
  const GrammarWritingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grammar & Writing')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: 'Grammar Studio'),
          ModuleTile(
            icon: Icons.rule_outlined,
            iconColor: AppColors.violet,
            title: 'Grammar lessons',
            subtitle: 'B1–B2 structured lessons and exercises',
            onTap: () => context.push('/learn/grammar/studio'),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Writing Studio'),
          ModuleTile(
            icon: Icons.edit_note_outlined,
            iconColor: AppColors.teal,
            title: 'Writing entries',
            subtitle: 'Drafts, prompts, revisions, feedback',
            onTap: () => context.push('/learn/grammar/writing'),
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.checklist_outlined,
            title: 'Mistake journal',
            subtitle: 'Review and mark mistakes understood',
            onTap: () => context.push('/learn/grammar/mistakes'),
          ),
        ],
      ),
    );
  }
}
