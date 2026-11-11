import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/services/providers.dart';
import 'core/database/app_database.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prefer portrait for focused learning UI
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final database = AppDatabase();
  final preferences = await database.getPreferences();
  final theme = switch (preferences.themeMode) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        themeModeProvider.overrideWith((ref) => theme),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const _AppLifecycleWrapper(child: LexiFlowApp()),
    ),
  );
}

/// Pauses running study sessions when the app is backgrounded.
class _AppLifecycleWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const _AppLifecycleWrapper({required this.child});

  @override
  ConsumerState<_AppLifecycleWrapper> createState() =>
      _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends ConsumerState<_AppLifecycleWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(studySessionServiceProvider).recoverInterrupted();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      try {
        await ref.read(studySessionServiceProvider).onAppPaused();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
