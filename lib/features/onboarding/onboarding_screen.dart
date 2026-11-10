import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';
import '../../app/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  final _nameController = TextEditingController();
  String _level = 'B1';
  String _target = 'B2';
  int _dailyMinutes = 60;
  String _englishPref = 'American';
  String _translation = 'Dari/Persian';
  final Set<String> _priorities = {'Reading', 'Vocabulary'};

  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      await db.updatePreferences({
        'display_name': _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        'english_level': _level,
        'target_level': _target,
        'daily_target_minutes': _dailyMinutes,
        'reading_minutes': (_dailyMinutes * 0.3).round().clamp(10, 40),
        'vocabulary_minutes': (_dailyMinutes * 0.25).round().clamp(8, 30),
        'listening_speaking_minutes':
            (_dailyMinutes * 0.25).round().clamp(8, 30),
        'grammar_writing_minutes': (_dailyMinutes * 0.2).round().clamp(6, 25),
        'english_preference': _englishPref,
        'translation_language': _translation,
        'learning_priorities': _priorities.toList().toString(),
        'onboarding_completed': 1,
      });
      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_page < 2) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Text('LexiFlow',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.violet,
                            fontWeight: FontWeight.w700,
                          )),
                  const Spacer(),
                  Text('${_page + 1} / 3',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcome(),
                  _buildProfile(),
                  _buildPreferences(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: PrimaryButton(
                label: _page == 2 ? 'Start Learning' : 'Continue',
                loading: _saving,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_stories_rounded,
                size: 36, color: AppColors.violet),
          ),
          const SizedBox(height: 28),
          Text('Welcome to LexiFlow',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Your calm, focused companion for moving from intermediate (B1) to upper-intermediate (B2) English — built to work offline first.',
            style:
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 28),
          _featureRow(Icons.menu_book_outlined, 'Reading & vocabulary'),
          _featureRow(Icons.headphones_outlined, 'Listening & speaking'),
          _featureRow(Icons.edit_note_outlined, 'Grammar & writing'),
          _featureRow(Icons.offline_bolt_outlined, 'Works fully offline'),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.teal),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About you', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Optional — you can change these anytime in Settings.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              hintText: 'How should we greet you?',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          Text('Current level', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['A2', 'B1', 'B2', 'C1'].map((l) {
              final selected = _level == l;
              return ChoiceChip(
                label: Text(l),
                selected: selected,
                onSelected: (_) => setState(() => _level = l),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('Target level', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['B1', 'B2', 'C1', 'C2'].map((l) {
              final selected = _target == l;
              return ChoiceChip(
                label: Text(l),
                selected: selected,
                onSelected: (_) => setState(() => _target = l),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Daily study target: $_dailyMinutes min',
              style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _dailyMinutes.toDouble(),
            min: 20,
            max: 120,
            divisions: 20,
            label: '$_dailyMinutes min',
            onChanged: (v) => setState(() => _dailyMinutes = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferences() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preferences', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Text('English variety',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'American', label: Text('American')),
              ButtonSegment(value: 'British', label: Text('British')),
            ],
            selected: {_englishPref},
            onSelectionChanged: (s) => setState(() => _englishPref = s.first),
          ),
          const SizedBox(height: 20),
          Text('Translation language',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _translation,
            items: const [
              DropdownMenuItem(
                  value: 'Dari/Persian', child: Text('Dari / Persian')),
              DropdownMenuItem(value: 'None', child: Text('None')),
            ],
            onChanged: (v) =>
                setState(() => _translation = v ?? 'Dari/Persian'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Text('Learning priorities',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Reading',
              'Vocabulary',
              'Listening',
              'Speaking',
              'Grammar',
              'Writing'
            ].map((p) {
              final selected = _priorities.contains(p);
              return FilterChip(
                label: Text(p),
                selected: selected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _priorities.add(p);
                  } else {
                    _priorities.remove(p);
                  }
                }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
