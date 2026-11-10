import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/services/ai_teacher_service.dart';
import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _apiKeyCtrl;
  UserPreference? _prefs;
  AiStatus? _aiStatus;
  bool _loading = true;
  bool _saving = false;
  AiProvider _selectedProvider = AiProvider.none;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _apiKeyCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final ai = ref.read(aiTeacherServiceProvider);
    final prefs = await db.getPreferences();
    final status = await ai.checkStatus();
    final provider = await ai.getConfiguredProvider();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _nameCtrl.text = prefs.displayName ?? '';
      _aiStatus = status;
      _selectedProvider = provider;
      _loading = false;
      final mode = prefs.themeMode;
      ref.read(themeModeProvider.notifier).state = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _savePrefs(Map<String, dynamic> data) async {
    setState(() => _saving = true);
    try {
      await ref.read(appDatabaseProvider).updatePreferences(data);
      ref.invalidate(dashboardProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _prefs == null) {
      return const Scaffold(body: LoadingView());
    }
    final p = _prefs!;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionHeader(title: 'Appearance'),
          LexiCard(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System'),
                  value: ThemeMode.system,
                  groupValue: ref.watch(themeModeProvider),
                  onChanged: (v) async {
                    ref.read(themeModeProvider.notifier).state = v!;
                    await _savePrefs({'theme_mode': 'system'});
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: ref.watch(themeModeProvider),
                  onChanged: (v) async {
                    ref.read(themeModeProvider.notifier).state = v!;
                    await _savePrefs({'theme_mode': 'light'});
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: ref.watch(themeModeProvider),
                  onChanged: (v) async {
                    ref.read(themeModeProvider.notifier).state = v!;
                    await _savePrefs({'theme_mode': 'dark'});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Profile'),
          LexiCard(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  onSubmitted: (v) => _savePrefs({
                    'display_name': v.trim().isEmpty ? null : v.trim(),
                  }),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Current level'),
                  trailing: Text(p.englishLevel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => _pickLevel(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Target level'),
                  trailing: Text(p.targetLevel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => _pickLevel(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Study plan'),
          LexiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily target: ${p.dailyTargetMinutes} min',
                    style: Theme.of(context).textTheme.titleSmall),
                Slider(
                  value: p.dailyTargetMinutes.toDouble(),
                  min: 20,
                  max: 120,
                  divisions: 20,
                  label: '${p.dailyTargetMinutes}',
                  onChanged: (v) {
                    setState(() {
                      _prefs = p.copyWith(dailyTargetMinutes: v.round());
                    });
                  },
                  onChangeEnd: (v) => _savePrefs({
                    'daily_target_minutes': v.round(),
                    'reading_minutes': (v * 0.3).round().clamp(10, 40),
                    'vocabulary_minutes': (v * 0.25).round().clamp(8, 30),
                    'listening_speaking_minutes':
                        (v * 0.25).round().clamp(8, 30),
                    'grammar_writing_minutes': (v * 0.2).round().clamp(6, 25),
                  }),
                ),
                Text('Translation: ${p.translationLanguage}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('English: ${p.englishPreference}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'AI Teacher (optional)'),
          LexiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _aiStatus?.message ?? 'Not configured',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AiProvider>(
                  value: _selectedProvider == AiProvider.none
                      ? AiProvider.openAi
                      : _selectedProvider,
                  items: const [
                    DropdownMenuItem(
                        value: AiProvider.openAi, child: Text('OpenAI')),
                    DropdownMenuItem(
                        value: AiProvider.anthropic, child: Text('Anthropic')),
                    DropdownMenuItem(
                        value: AiProvider.custom, child: Text('Custom')),
                  ],
                  onChanged: (v) => setState(
                      () => _selectedProvider = v ?? AiProvider.openAi),
                  decoration: const InputDecoration(labelText: 'Provider'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    hintText: 'Stored in platform secure storage',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  await ref
                                      .read(aiTeacherServiceProvider)
                                      .saveApiKey(
                                        _selectedProvider,
                                        _apiKeyCtrl.text,
                                      );
                                  _apiKeyCtrl.clear();
                                  await _load();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('API key saved securely')),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _saving = false);
                                }
                              },
                        child: const Text('Save key'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(aiTeacherServiceProvider)
                            .clearCredentials();
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Credentials cleared')),
                          );
                        }
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Keys never leave the device. AI features remain optional and offline-first.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('LexiFlow Phase 1 · Offline-first',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _pickLevel(bool current) async {
    final levels =
        current ? ['A2', 'B1', 'B2', 'C1'] : ['B1', 'B2', 'C1', 'C2'];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: levels
              .map((l) => ListTile(
                    title: Text(l),
                    onTap: () => Navigator.pop(ctx, l),
                  ))
              .toList(),
        ),
      ),
    );
    if (chosen == null) return;
    if (current) {
      await _savePrefs({'english_level': chosen});
    } else {
      await _savePrefs({'target_level': chosen});
    }
  }
}
