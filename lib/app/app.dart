import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/settings_screen.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../core/services/maintenance_controller.dart';
import '../core/services/providers.dart';
import '../core/widgets/study_session_dock.dart';

class LexiFlowApp extends ConsumerWidget {
  const LexiFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final maintenance = ref.watch(maintenanceControllerProvider);
    if (maintenance.active) {
      return MaterialApp(
        key: const ValueKey('maintenance'),
        theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: themeMode,
        home: Scaffold(body: SafeArea(child: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!maintenance.done) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Semantics(liveRegion: true, child: Text(maintenance.message, textAlign: TextAlign.center)),
            if (maintenance.done) FilledButton(
              onPressed: () async {
                try {
                  ref.read(appDatabaseProvider).retire();
                  ref.read(appGenerationProvider.notifier).state++;
                  final prefs = await ref.read(appDatabaseProvider).getPreferences();
                  ref.read(themeModeProvider.notifier).state = switch (prefs.themeMode) {
                    'dark' => ThemeMode.dark, 'light' => ThemeMode.light,
                    _ => ThemeMode.system,
                  };
                  await ref.read(studySessionServiceProvider).recoverInterrupted();
                  maintenance.leave();
                } catch (_) {
                  maintenance.progress('Could not reopen learning data. The recovery snapshot is retained. Restart the app to retry recovery.');
                }
              }, child: const Text('Return to learning')),
          ]),
        )))),
      );
    }
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'LexiFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => StudySessionDock(child: child!),
    );
  }
}
