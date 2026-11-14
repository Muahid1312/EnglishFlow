import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/common_widgets.dart';
import 'dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final hour = DateTime.now().hour;
    final greeting = greetingForHour(hour);

    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(message: 'Loading your progress…'),
          error: (e, _) => ErrorView(
            message: 'Could not load dashboard.\n$e',
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(dashboardProvider),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.displayName != null &&
                                        data.displayName!.isNotEmpty
                                    ? '$greeting, ${data.displayName}'
                                    : greeting,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('EEEE, MMM d')
                                    .format(DateTime.now()),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => context.push('/settings'),
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Settings',
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Progress card
                        LexiCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ProgressRing(
                                    progress: data.progress,
                                    size: 100,
                                    centerLabel:
                                        '${data.completedMinutesToday}',
                                    subLabel: 'min',
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Today\'s goal',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${data.completedMinutesToday} / ${data.dailyTargetMinutes} min',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                color: AppColors.violet,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (data.goalMet)
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 18,
                                                  color: AppColors.success),
                                              SizedBox(width: 6),
                                              Text('Goal reached!',
                                                  style: TextStyle(
                                                      color: AppColors.success,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          )
                                        else
                                          Text(
                                            '${(data.dailyTargetMinutes - data.completedMinutesToday).clamp(0, 999)} min remaining',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _StatChip(
                                      icon: Icons.local_fire_department,
                                      label: '${data.streak} day streak',
                                      color: AppColors.warning),
                                  const SizedBox(width: 10),
                                  _StatChip(
                                      icon: Icons.style_outlined,
                                      label: '${data.savedWords} words',
                                      color: AppColors.teal),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Continue learning'),
                        ModuleTile(
                          icon: Icons.play_circle_outline,
                          iconColor: AppColors.violet,
                          title: 'Today’s learning plan',
                          subtitle:
                              'A balanced plan using your saved learning material',
                          onTap: () => context.push('/plan'),
                        ),
                        const SizedBox(height: 12),
                        if (data.dueReviews > 0)
                          ModuleTile(
                            icon: Icons.replay,
                            iconColor: AppColors.teal,
                            title: 'Vocabulary reviews',
                            subtitle: '${data.dueReviews} cards due',
                            badge: '${data.dueReviews}',
                            onTap: () => context.push('/learn/vocabulary'),
                          )
                        else
                          ModuleTile(
                            icon: Icons.replay,
                            iconColor: AppColors.teal,
                            title: 'Vocabulary reviews',
                            subtitle: 'No reviews due yet',
                            onTap: () => context.push('/learn/vocabulary'),
                          ),
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Quick access'),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickAccess(
                                icon: Icons.menu_book_outlined,
                                label: 'Reading',
                                minutes: data.readingTarget,
                                onTap: () => context.push('/learn/reading'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickAccess(
                                icon: Icons.headphones_outlined,
                                label: 'Listening',
                                minutes: data.listeningTarget,
                                onTap: () => context.push('/learn/listening'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickAccess(
                                icon: Icons.edit_note_outlined,
                                label: 'Writing',
                                minutes: data.grammarTarget,
                                onTap: () => context.push('/learn/grammar'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Recent activity'),
                        if (data.recentActivities.isEmpty)
                          LexiCard(
                            child: Text(
                              'No study sessions yet. Start your first session from Learn.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        else
                          ...data.recentActivities.take(5).map((a) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: LexiCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(_iconForActivity(a.type),
                                        size: 20, color: AppColors.violet),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _labelForActivity(a),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ),
                                    Text(
                                      a.localDate,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForActivity(String type) {
    switch (type) {
      case 'session_completed':
        return Icons.check_circle_outline;
      case 'session_interrupted':
        return Icons.pause_circle_outline;
      default:
        return Icons.history;
    }
  }

  String _labelForActivity(dynamic a) {
    final module = a.module ?? 'study';
    if (a.type == 'session_completed') return 'Completed $module session';
    if (a.type == 'session_interrupted') return 'Interrupted $module session';
    return a.type;
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  final IconData icon;
  final String label;
  final int minutes;
  final VoidCallback onTap;

  const _QuickAccess(
      {required this.icon,
      required this.label,
      required this.minutes,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LexiCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: AppColors.violet),
          const SizedBox(height: 8),
          Text(label,
              style: Theme.of(context).textTheme.labelLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text('$minutes min', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
