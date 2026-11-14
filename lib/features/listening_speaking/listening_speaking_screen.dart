import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/services/providers.dart';
import '../../core/services/analytics_service.dart';

final listeningInsightsProvider=FutureProvider<Map<String,dynamic>>((ref)=>AnalyticsService(ref.watch(appDatabaseProvider)).listening());

class ListeningSpeakingScreen extends ConsumerWidget {
  const ListeningSpeakingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listening & Speaking')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ref.watch(listeningInsightsProvider).when(
            loading:()=>const LinearProgressIndicator(),
            error:(_,__)=>TextButton(onPressed:()=>ref.invalidate(listeningInsightsProvider),child:const Text('Retry listening insights')),
            data:(stats)=>LexiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('Listening & speaking activity',style:TextStyle(fontWeight:FontWeight.w600)),
              Text('${(stats['listeningSeconds'] as int)~/60} listening minutes · ${(stats['combinedSeconds'] as int)~/60} combined listening/speaking minutes'),
              Text('${(stats['aiStudySeconds'] as int)~/60} AI study minutes · ${(stats['shadowingStudySeconds'] as int)~/60} shadowing study minutes'),
              Text('${stats['comprehensionExercises']} completed comprehension exercises · ${stats['correct']}/${stats['graded']} objective answers correct'),
              Text('${stats['shadowingAttempts']} saved shadowing attempts · ${stats['speakingTakes']} speaking takes · ${stats['aiConversations']} conversations with real replies'),
              Text('${stats['recordedSeconds']} seconds reported by recording durations, including drafts. These are not additional study minutes.'),
              const Text('Minutes use finished study sessions only. Older/planned listening–speaking sessions remain combined; they are not added again to listening-only totals. No fluency score is inferred.'),
              for(final event in stats['recent'] as List) Text('${event['type']} · ${event['local_date']}'),
            ])),
          ),
          const SizedBox(height:20),
          const SectionHeader(title: 'Listening Studio'),
          ModuleTile(
            icon: Icons.headphones_outlined,
            iconColor: AppColors.violet,
            title: 'Listening library',
            subtitle: 'Import audio, play offline, bookmarks & transcripts',
            onTap: () async {await context.push('/learn/listening/library');ref.invalidate(listeningInsightsProvider);},
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Speaking Studio'),
          ModuleTile(
            icon: Icons.mic_none,
            iconColor: AppColors.teal,
            title: 'Speaking prompts',
            subtitle: 'Record answers to B1–B2 prompts',
            onTap: () async {await context.push('/learn/listening/speaking');ref.invalidate(listeningInsightsProvider);},
          ),
          const SizedBox(height: 12),
          ModuleTile(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.violetSoft,
            title: 'AI conversation',
            subtitle: 'Optional text tutor when API key is configured',
            onTap: () async {await context.push('/learn/listening/ai');ref.invalidate(listeningInsightsProvider);},
          ),
        ],
      ),
    );
  }
}
