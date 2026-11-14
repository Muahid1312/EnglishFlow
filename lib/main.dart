import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/services/providers.dart';
import 'core/database/app_database.dart';
import 'features/settings/settings_screen.dart';
import 'core/services/maintenance_controller.dart';
import 'core/widgets/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Prefer portrait for focused learning UI
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase();
    late UserPreference preferences;
    try {
      preferences = await database.getPreferences();
    } finally {
      database.close();
    }
    final theme = switch (preferences.themeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    runApp(
      ProviderScope(
        overrides: [
          themeModeProvider.overrideWith((ref) => theme),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const _AppLifecycleWrapper(child: LexiFlowApp()),
      ),
    );
  } catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: FlutterError(
          'Startup failed (${error.runtimeType}). Learning data was not reset.'),
      stack: stack,
      library: 'LexiFlow startup',
    ));
    runApp(MaterialApp(
      title: 'LexiFlow',
      home: Scaffold(
          body: SafeArea(
              child: ErrorView(
        message:
            'Could not open LexiFlow. Your learning data has not been reset. Check available storage and retry. If this continues, keep the app installed and preserve your backup.',
        onRetry: () {
          unawaited(main());
        },
      ))),
    ));
  }
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
    unawaited(_recoverInterrupted());
  }

  Future<void> _recoverInterrupted() async {
    try {
      await ref.read(studySessionServiceProvider).recoverInterrupted();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception:
            FlutterError('Study timer recovery failed (${error.runtimeType}).'),
        stack: stack,
        library: 'LexiFlow study timer',
      ));
    }
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
      if (ref.read(maintenanceControllerProvider).active) return;
      try {
        await ref.read(studySessionServiceProvider).onAppPaused();
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception:
              FlutterError('Study timer pause failed (${error.runtimeType}).'),
          stack: stack,
          library: 'LexiFlow study timer',
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
