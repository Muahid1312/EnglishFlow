import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';

class ListeningSpeakingScreen extends ConsumerWidget {
  const ListeningSpeakingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listening & Speaking')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionHeader(title: 'Listening Studio'),
          ModuleTile(
            icon: Icons.headphones_outlined,
            iconColor: AppColors.violet,
            title: 'Listening library',
            subtitle: 'Import audio, play offline, bookmarks & transcripts',
            onTap: () => context.push('/learn/listening/library'),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Speaking Studio'),
          ModuleTile(
            icon: Icons.mic_none,
            iconColor: AppColors.teal,
            title: 'Speaking prompts',
            subtitle: 'Record answers to B1–B2 prompts',
            onTap: () => context.push('/learn/listening/speaking'),
          ),
          const SizedBox(height: 12),
          ModuleTile(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.violetSoft,
            title: 'AI conversation',
            subtitle: 'Optional text tutor when API key is configured',
            onTap: () => context.push('/learn/listening/ai'),
          ),
        ],
      ),
    );
  }
}
