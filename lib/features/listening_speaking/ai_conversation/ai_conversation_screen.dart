import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ai_teacher_service.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

/// Text-based AI conversation. Real provider calls only when credentials exist.
/// No fake speech recognition or invented scores.
class AiConversationScreen extends ConsumerStatefulWidget {
  const AiConversationScreen({super.key});

  @override
  ConsumerState<AiConversationScreen> createState() =>
      _AiConversationScreenState();
}

class _AiConversationScreenState extends ConsumerState<AiConversationScreen> {
  final _input = TextEditingController();
  final _messages = <_Msg>[];
  String? _conversationId;
  AiStatus? _status;
  bool _sending = false;
  String _mode = 'everyday';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final status = await ref.read(aiTeacherServiceProvider).checkStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _ensureConversation() async {
    if (_conversationId != null) return;
    final id = newId();
    final provider =
        await ref.read(aiTeacherServiceProvider).getConfiguredProvider();
    await ref.read(appDatabaseProvider).insertAiConversation(
          id,
          provider: provider.name,
          title: 'Conversation · $_mode',
        );
    _conversationId = id;
    final opener = _openerForMode(_mode);
    _messages.add(_Msg(role: 'assistant', text: opener));
    await ref
        .read(appDatabaseProvider)
        .insertAiMessage(newId(), id, 'assistant', opener);
  }

  String _openerForMode(String mode) {
    switch (mode) {
      case 'university':
        return 'Let\'s practice university English. Tell me about a class or project you are working on.';
      case 'technology':
        return 'Let\'s talk about technology. What is an app or tool you use often, and why?';
      case 'job_interview':
        return 'I will act as an interviewer. First question: Can you briefly introduce yourself and your background?';
      case 'free':
        return 'This is free conversation practice. What would you like to talk about today?';
      default:
        return 'Hi! Let\'s practice everyday English. How has your day been so far?';
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await _ensureConversation();
    setState(() {
      _messages.add(_Msg(role: 'user', text: text));
      _sending = true;
      _input.clear();
    });
    await ref
        .read(appDatabaseProvider)
        .insertAiMessage(newId(), _conversationId!, 'user', text);

    final status = _status;
    if (status == null || !status.isReady) {
      final reply =
          'AI is not configured. Your message was saved locally. Add an API key in Settings to get live tutoring replies. Offline practice still counts when you record speaking separately.';
      setState(() {
        _messages
            .add(_Msg(role: 'assistant', text: reply, isLocalFallback: true));
        _sending = false;
      });
      await ref
          .read(appDatabaseProvider)
          .insertAiMessage(newId(), _conversationId!, 'assistant', reply);
      return;
    }

    // Phase 3: credentials exist but we do not ship a hardcoded live HTTP call
    // without user network intent. Show an honest status — wire real HTTP in Phase 4+
    // when a backend proxy or explicit provider client is chosen.
    final reply =
        'Credentials are stored securely (${status.provider.name}). Live provider HTTP calls are not enabled in this build to avoid accidental network use and secret leakage. Your messages are saved offline. A real chat completion client can be attached next without changing this UI.';
    setState(() {
      _messages
          .add(_Msg(role: 'assistant', text: reply, isLocalFallback: true));
      _sending = false;
    });
    await ref
        .read(appDatabaseProvider)
        .insertAiMessage(newId(), _conversationId!, 'assistant', reply);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Conversation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status?.isReady == true
                      ? 'AI ready (${_status!.provider.name}) — text mode'
                      : 'AI not configured — messages stay on device',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final m in [
                        'everyday',
                        'university',
                        'technology',
                        'job_interview',
                        'free'
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(m.replaceAll('_', ' ')),
                            selected: _mode == m,
                            onSelected: (_) {
                              if (_messages.isNotEmpty) return;
                              setState(() => _mode = m);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Voice transcription and TTS are unavailable unless a supported engine is configured. No fake speech recognition.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _messages.isEmpty
                ? const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Start a conversation',
                    message:
                        'Choose a mode and send a message. Works offline for saving practice; live AI needs a key in Settings.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.text),
                              if (m.isLocalFallback)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                      'Local note — not a live model reply',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration:
                          const InputDecoration(hintText: 'Type your answer…'),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Msg {
  final String role;
  final String text;
  final bool isLocalFallback;
  _Msg({required this.role, required this.text, this.isLocalFallback = false});
}
