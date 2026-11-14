import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import 'ai_teacher_service.dart';
import 'study_session_service.dart';
import 'daily_plan_service.dart';
import 'listening_downloads.dart';

final appGenerationProvider = StateProvider<int>((ref) => 0);

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main');
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  ref.watch(appGenerationProvider);
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final dailyPlanServiceProvider = Provider<DailyPlanService>((ref) =>
    DailyPlanService(
        ref.watch(appDatabaseProvider), ref.watch(studySessionServiceProvider),
        ai: ref.watch(aiTeacherServiceProvider)));

final studySessionServiceProvider =
    ChangeNotifierProvider<StudySessionService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudySessionService(db);
});

final aiTeacherServiceProvider = Provider<AiTeacherService>((ref) {
  return SecureAiTeacherService();
});

final listeningDownloadsProvider =
    ChangeNotifierProvider<ListeningDownloads>((ref) {
  return ListeningDownloads(ref.watch(appDatabaseProvider));
});
