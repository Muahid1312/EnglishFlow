import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import 'ai_teacher_service.dart';
import 'study_session_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main');
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final studySessionServiceProvider =
    ChangeNotifierProvider<StudySessionService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudySessionService(db);
});

final aiTeacherServiceProvider = Provider<AiTeacherService>((ref) {
  return SecureAiTeacherService();
});
