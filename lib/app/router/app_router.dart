import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/providers.dart';
import '../../features/books/books_screen.dart';
import '../../features/courses/course_screens.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/learn_hub_screen.dart';
import '../../features/grammar_writing/grammar_writing_screen.dart';
import '../../features/grammar_writing/grammar/grammar_studio_screen.dart';
import '../../features/grammar_writing/grammar/grammar_lesson_screen.dart';
import '../../features/grammar_writing/writing/writing_studio_screen.dart';

import '../../features/listening_speaking/listening_speaking_screen.dart';
import '../../features/listening_speaking/listening/listening_library_screen.dart';
import '../../features/listening_speaking/listening/audio_player_screen.dart';
import '../../features/listening_speaking/speaking/speaking_studio_screen.dart';
import '../../features/listening_speaking/ai_conversation/ai_conversation_screen.dart';

import '../../features/onboarding/onboarding_screen.dart';
import '../../features/progress/progress_screen.dart';

import '../../features/assessments/assessments_screen.dart';

import '../../features/reading/reading_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/vocabulary/vocabulary_screen.dart';
import '../../features/daily_plan/daily_plan_screen.dart';
import '../../features/backup/backup_screen.dart';
import '../../features/vocabulary/word_detail_screen.dart';
import '../../features/mistake_coach/mistake_practice_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  ref.watch(appGenerationProvider);
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    redirect: (context, state) async {
      final db = ref.read(appDatabaseProvider);
      final prefs = await db.getPreferences();
      final onboarded = prefs.onboardingCompleted;
      final loc = state.matchedLocation;
      if (!onboarded && loc != '/onboarding') return '/onboarding';
      if (onboarded && loc == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNav(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/learn',
                builder: (context, state) => const LearnHubScreen(),
                routes: [
                  GoRoute(
                      path: 'reading',
                      builder: (_, __) => const ReadingScreen(),
                      routes: [
                        GoRoute(
                            path: ':id',
                            builder: (_, s) => ArticleReaderScreen(
                                articleId: s.pathParameters['id']!))
                      ]),
                  GoRoute(
                      path: 'vocabulary',
                      builder: (_, __) => const VocabularyScreen(),
                      routes:[GoRoute(path:'word/:id',builder:(_,s)=>WordDetailScreen(entryId:s.pathParameters['id']!))]),
                  GoRoute(
                    path: 'listening',
                    builder: (_, __) => const ListeningSpeakingScreen(),
                    routes: [
                      GoRoute(
                        path: 'library',
                        builder: (_, __) => const ListeningLibraryScreen(),
                      ),
                      GoRoute(
                        path: 'player/:id',
                        builder: (_, state) => AudioPlayerScreen(
                            lessonId: state.pathParameters['id']!,initialPositionMs:int.tryParse(state.uri.queryParameters['startMs']??'')),
                      ),
                      GoRoute(
                        path: 'speaking',
                        builder: (_, __) => const SpeakingStudioScreen(),
                      ),
                      GoRoute(
                        path: 'ai',
                        builder: (_, __) => const AiConversationScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'grammar',
                    builder: (_, __) => const GrammarWritingScreen(),
                    routes: [
                      GoRoute(
                          path: 'studio',
                          builder: (_, __) => const GrammarStudioScreen()),
                      GoRoute(
                        path: 'lesson/:id',
                        builder: (_, s) => GrammarLessonScreen(
                            lessonId: s.pathParameters['id']!),
                      ),
                      GoRoute(
                          path: 'writing',
                          builder: (_, __) => const WritingStudioScreen()),
                      GoRoute(
                        path: 'writing/:id',
                        builder: (_, s) => WritingEditorScreen(
                            entryId: s.pathParameters['id']!),
                      ),
                      GoRoute(
                          path: 'mistakes',
                          builder: (_, __) => const MistakeJournalScreen(),
                          routes:[GoRoute(path:'practice',builder:(_,s)=>MistakePracticeScreen(category:s.uri.queryParameters['category']))]),
                    ],
                  ),
                  GoRoute(path:'courses', builder:(_,__)=>const CoursesScreen(),routes:[GoRoute(path:'lesson/:id',builder:(_,s)=>CourseLessonScreen(lessonId:s.pathParameters['id']!))]),
                  GoRoute(
                    path: 'books',
                    builder: (_, __) => const BooksScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (_, s) =>
                            BookDetailScreen(bookId: s.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'read',
                            builder: (_, s) => BookReaderScreen(
                                bookId: s.pathParameters['id']!, initialPage:int.tryParse(s.uri.queryParameters['page']??'')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/practice',
                builder: (context, state) =>
                    const LearnHubScreen(), // reuse for Phase 1
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (context, state) => const ProgressScreen(),
                routes: [
                  GoRoute(
                      path: 'assessments',
                      builder: (_, __) => const AssessmentsScreen(),
                      routes: [
                        GoRoute(
                            path: ':id',
                            builder: (_, s) => AssessmentTakeScreen(
                                assessmentId: s.pathParameters['id']!)),
                      ]),
                  GoRoute(
                      path: 'certificates',
                      builder: (_, __) => const CertificatesScreen()),
                  GoRoute(
                      path: 'export', builder: (_, __) => const ExportScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/plan',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const DailyPlanScreen(),
      ),
      GoRoute(
        path: '/backup',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class ScaffoldWithNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNav({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Learn'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Practice'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Progress'),
        ],
      ),
    );
  }
}
