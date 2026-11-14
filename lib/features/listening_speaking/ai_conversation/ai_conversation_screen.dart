import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/ai_teacher_service.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/services/article_import_service.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/content/conversation_scenarios.dart';
import '../../../core/services/practice_timer.dart';
import '../../../core/services/pronunciation_service.dart';
import '../../vocabulary/word_editor.dart';
import '../../grammar_writing/writing/writing_history_screens.dart';

class AiConversationScreen extends ConsumerStatefulWidget {
  const AiConversationScreen({super.key});
  @override
  ConsumerState<AiConversationScreen> createState() =>
      _AiConversationScreenState();
}

class _AiConversationScreenState extends ConsumerState<AiConversationScreen> {
  final _input = TextEditingController();
  late final AppDatabase _db;
  late final AiTeacherService _ai;
  List<Map<String, dynamic>> _messages = [];
  String? _conversationId;
  String _title = 'AI Teacher', _mode = 'everyday';
  bool _loading = true, _sending = false;
  int _offset = 0;
  String? _error;
  AiStatus? _status;
  Timer? _poll;
  String? _activeRequest;
  String _providerDisclosure = 'Your configured provider';
  late final PracticeTimer _timer;
  final _selections = <String, TextSelection>{};
  final _speech = PronunciationService();
  String? _speechNotice;
  bool _speakingSelection = false;
  int _speechGeneration = 0;
  @override
  void initState() {
    super.initState();
    _db = ref.read(appDatabaseProvider);
    _ai = ref.read(aiTeacherServiceProvider);
    final active = ref.read(studySessionServiceProvider).active;
    _timer = PracticeTimer(
        ref.read(studySessionServiceProvider),
        active?.module == 'listening_speaking'
            ? 'listening_speaking'
            : 'ai_conversation');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final status = await _ai.checkStatus();
      final configuration = await _ai.getConfiguration();
      _providerDisclosure =
          '${status.provider.name} · ${configuration.model} · ${Uri.tryParse(configuration.endpoint)?.host ?? 'configured endpoint'}';
      final conversations = await _db.getAiConversations();
      final selected = _conversationId == null
          ? null
          : await _db.getAiConversation(_conversationId!);
      if (!mounted) return;
      _status = status;
      if (conversations.isNotEmpty) {
        final c = selected ?? conversations.first;
        _conversationId = c['id'] as String;
        _title = c['title'] as String? ?? 'AI Teacher';
        _mode =
            conversationScenario(c['scenario_id'] as String? ?? 'everyday').id;
      } else {
        _conversationId = null;
        _title = 'AI Teacher';
      }
      await _refresh(interrupted: true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load conversations.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh({bool interrupted = false}) async {
    final id = _conversationId;
    if (id == null) {
      if (mounted) setState(() => _messages = []);
      return;
    }
    var messages = await _db.getAiMessages(id, offset: _offset);
    if (interrupted) {
      for (final m in messages.where(
          (m) => m['role'] == 'user' && m['request_state'] == 'pending')) {
        if (!_ai.isRequestActive(m['id'] as String)) {
          await _db.setAiRequestState(m['id'] as String, 'interrupted',
              errorCode: 'interrupted');
        }
      }
      messages = await _db.getAiMessages(id, offset: _offset);
    }
    if (!mounted || _conversationId != id) return;
    setState(() => _messages = messages);
    _poll?.cancel();
    if (messages.any((m) => m['request_state'] == 'pending')) {
      _poll = Timer(const Duration(seconds: 1), () {
        if (mounted) _refresh(interrupted: true);
      });
    }
  }

  Future<void> _ensureConversation() async {
    if (_conversationId != null) return;
    final id = newId();
    AiProvider provider = AiProvider.none;
    try {
      provider = await _ai.getConfiguredProvider();
    } catch (_) {}
    await _db.insertAiConversation(id,
        provider: provider.name,
        title: 'Conversation · $_mode',
        scenarioId: _mode);
    _conversationId = id;
    _title = 'Conversation · $_mode';
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _loading || _offset != 0) return;
    setState(() => _sending = true);
    try {
      await _ensureConversation();
      await _timer.start();
      final request = await _db.beginAiRequest(_conversationId!, text);
      if (mounted) _input.clear();
      await _refresh();
      await _request(request);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'Could not save message. Your typed text is retained.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _request(String requestId) async {
    final timer = ref.read(studySessionServiceProvider);
    _activeRequest = requestId;
    final conversationId = _conversationId!;
    final scenarioId = _mode;
    try {
      final current = (await _db.db).select(
          'SELECT request_state FROM ai_messages WHERE id=?', [requestId]);
      if (current.isEmpty || current.single['request_state'] == 'complete') {
        _activeRequest = null;
        if (mounted) await _refresh();
        return;
      }
      await _db.setAiRequestState(requestId, 'pending');
      final history = await _db.getAiMessages(conversationId);
      final requestIndex = history.indexWhere((m) => m['id'] == requestId);
      if (requestIndex < 0) {
        throw const AiFailure(
            AiError.rejected, 'Request is not in the current conversation.');
      }
      final context = history
          .take(requestIndex + 1)
          .where((m) =>
              (m['purpose'] == 'conversation' || m['id'] == requestId) &&
              (m['role'] == 'user' ||
                  (m['role'] == 'assistant' && m['is_local'] == 0)))
          .map((m) => AiMessage(m['role'] as String, m['content'] as String))
          .toList();
      final response = await timer.withoutAiWaitingTime(() =>
          _ai.completeCoached(context,
              scenarioId: scenarioId,
              feedback: history[requestIndex]['purpose'] == 'feedback',
              requestId: requestId));
      await _db.finishAiRequest(requestId, response);
      if (mounted) setState(() => _error = null);
    } on AiFailure catch (error) {
      await _db.setAiRequestState(
          requestId, error.code == AiError.cancelled ? 'cancelled' : 'error',
          errorCode: error.code.name);
      if (mounted) {
        setState(() => _error = error.retryAfter == null
            ? error.message
            : '${error.message} Retry after ${error.retryAfter!.inSeconds} seconds.');
      }
    } catch (_) {
      await _db.setAiRequestState(requestId, 'error', errorCode: 'unavailable');
      if (mounted) {
        setState(() => _error =
            'AI request could not finish. Your message is saved locally.');
      }
    }
    _activeRequest = null;
    if (mounted) await _refresh();
  }

  Future<void> _retry(String request) async {
    if (_sending || _ai.isRequestActive(request)) return;
    setState(() => _sending = true);
    try {
      await _request(request);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _history() async {
    final selected = await showDialog<String>(
        context: context, builder: (_) => _ConversationDialog(db: _db));
    if (!mounted) return;
    _offset = 0;
    if (selected != null) _conversationId = selected;
    await _bootstrap();
  }

  Future<void> _new() async {
    final title = await showDialog<String>(
        context: context,
        builder: (_) =>
            const _ConversationNameDialog(initial: 'New conversation'));
    if (title == null || !mounted) return;
    try {
      final id = newId();
      await _db.insertAiConversation(id, title: title, scenarioId: _mode);
      _conversationId = id;
      _title = title;
      _offset = 0;
      _error = null;
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create conversation.');
    }
  }

  Future<void> _finishStudy() async {
    final id = _timer.id;
    if (id == null || _timer.sessions.active?.id != id) return;
    try {
      final linked = (await _db.db).select(
          'SELECT activity_id FROM plan_sessions WHERE session_id=?', [id]);
      if (linked.isEmpty) {
        await _timer.sessions.finish();
      } else {
        await ref
            .read(dailyPlanServiceProvider)
            .complete(linked.single['activity_id'] as String);
      }
      ref.invalidate(dashboardProvider);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not finish the study activity. Your conversation remains saved.');
    }
  }

  Future<void> _cancel() async {
    final id = _activeRequest;
    if (id == null) return;
    final cancelled = _ai.cancelRequest(id);
    if (mounted)
      setState(() => _error = cancelled
          ? 'Cancellation requested. The provider may already have processed the request.'
          : 'This provider adapter cannot cancel the in-flight operation; it may still complete.');
  }

  Future<void> _feedback() async {
    if (_sending || _conversationId == null) return;
    final consent = await showConfirmDialog(context,
        title: 'Request conversation feedback?',
        message:
            'Send this conversation to $_providerDisclosure for a short correction/vocabulary summary? Your original messages remain unchanged.');
    if (consent != true || !mounted) return;
    setState(() => _sending = true);
    try {
      final request = await _db.beginAiRequest(_conversationId!,
          'Please provide the optional short feedback summary for our conversation.',
          purpose: 'feedback');
      await _refresh();
      await _request(request);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not request feedback. Your conversation is preserved.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _selected(Map<String, dynamic> message) {
    final selection = _selections[message['id']];
    return selection != null && selection.isValid && !selection.isCollapsed
        ? selection.textInside(message['content'] as String).trim()
        : '';
  }

  Future<void> _speakSelection(Map<String, dynamic> message) async {
    final text = _selected(message);
    if (text.isEmpty || text.length > 100) {
      setState(() => _speechNotice =
          'Select a phrase of up to 100 characters in the reply first.');
      return;
    }
    final generation = ++_speechGeneration;
    setState(() => _speakingSelection = true);
    try {
      final result = await _speech.speak(text);
      if (mounted && generation == _speechGeneration)
        setState(() => _speechNotice = result['stopped'] == true
            ? 'Playback stopped.'
            : 'Played using ${result['locale']}. Offline playback depends on installed voice data.');
    } catch (_) {
      if (mounted && generation == _speechGeneration)
        setState(() => _speechNotice =
            'Pronunciation unavailable. Check the installed Android English TTS engine/voice.');
    } finally {
      if (mounted && generation == _speechGeneration)
        setState(() => _speakingSelection = false);
    }
  }

  Future<void> _saveWord(Map<String, dynamic> message) async {
    final selected = _selected(message);
    await showDialog<bool>(
        context: context,
        builder: (_) => WordEditorDialog(
            db: _db,
            initialWord: selected.length <= 100 ? selected : '',
            initialContext: selected.isNotEmpty
                ? sourceSentence(
                    message['content'] as String,
                    _selections[message['id']]!.start,
                    _selections[message['id']]!.end)
                : null,
            initialSource: 'AI conversation: $_title'));
  }

  Future<void> _saveMistake(Map<String, dynamic> message) async {
    final preceding = _messages
        .takeWhile((m) => m['id'] != message['id'])
        .where((m) => m['role'] == 'user' && m['purpose'] == 'conversation')
        .toList();
    await showDialog<bool>(
        context: context,
        builder: (_) => MistakeEditorDialog(
            db: _db,
            initialOriginal:
                preceding.isEmpty ? '' : preceding.last['content'] as String,
            initialCorrection: _selected(message),
            sourceLabel: 'AI conversation: $_title'));
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_timer.pause().catchError((Object _) {}));
    unawaited(_speech.stop());
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
        studySessionServiceProvider.select((s) => (s.active?.id, s.isRunning)));
    final users = _messages.where((m) => m['role'] == 'user').toList();
    final retry = users.isEmpty ? null : users.last;
    return Scaffold(
        appBar: AppBar(title: const Text('AI Teacher'), actions: [
          IconButton(
              tooltip: 'Conversations',
              onPressed: _sending ? null : _history,
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'New conversation',
              onPressed: _sending ? null : _new,
              icon: const Icon(Icons.add)),
          IconButton(
              tooltip: 'Refresh conversation',
              onPressed: () => _bootstrap(),
              icon: const Icon(Icons.refresh)),
        ]),
        body: _loading
            ? const LoadingView()
            : Column(children: [
                Flexible(
                    flex: 2,
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  Text(_status?.message ??
                                      'Configure AI in Settings.'),
                                  const Text(
                                      'Send shares conversation text with your configured provider. No writing, audio, or textbook files are uploaded automatically.'),
                                  Text('Destination: $_providerDisclosure'),
                                  DropdownButtonFormField<String>(
                                      value: _mode,
                                      isExpanded: true,
                                      items: conversationScenarios
                                          .map((s) => DropdownMenuItem(
                                              value: s.id,
                                              child: Text(s.title)))
                                          .toList(),
                                      onChanged: _sending ||
                                              _messages.isNotEmpty
                                          ? null
                                          : (mode) async {
                                              final id = _conversationId;
                                              if (id != null)
                                                (await _db.db).execute(
                                                    'UPDATE ai_conversations SET scenario_id=? WHERE id=?',
                                                    [mode, id]);
                                              if (mounted)
                                                setState(() => _mode = mode!);
                                            },
                                      decoration: const InputDecoration(
                                          labelText: 'Conversation scenario')),
                                  Text(
                                      '${conversationScenario(_mode).level} · ${conversationScenario(_mode).goal}'),
                                  const Text(
                                      'Text chat requires your configured provider. Select a short reply phrase to speak it using Android TTS; some voices require network access. Speech recognition is unavailable: no transcription or speaking score is fabricated.'),
                                  const Text(
                                      'Optional feedback becomes available after three real AI replies.'),
                                  if (_speakingSelection)
                                    TextButton(
                                        onPressed: () async {
                                          ++_speechGeneration;
                                          await _speech.stop();
                                          if (mounted)
                                            setState(() {
                                              _speakingSelection = false;
                                              _speechNotice =
                                                  'Playback stopped.';
                                            });
                                        },
                                        child: const Text('Stop speech')),
                                  Wrap(spacing: 8, children: [
                                    TextButton(
                                        onPressed: _sending ||
                                                _offset != 0 ||
                                                _messages
                                                        .where((m) =>
                                                            m['role'] ==
                                                                'assistant' &&
                                                            m['is_local'] ==
                                                                0 &&
                                                            m['purpose'] ==
                                                                'conversation')
                                                        .length <
                                                    3
                                            ? null
                                            : _feedback,
                                        child: const Text(
                                            'Request AI feedback summary')),
                                    if (_sending && _activeRequest != null)
                                      TextButton(
                                          onPressed: _cancel,
                                          child: const Text('Cancel request')),
                                    TextButton(
                                        onPressed: _sending ||
                                                _timer.id == null ||
                                                _timer.sessions.active?.id !=
                                                    _timer.id
                                            ? null
                                            : _finishStudy,
                                        child: const Text(
                                            'Finish study activity')),
                                  ]),
                                  if (_speechNotice != null)
                                    Text(_speechNotice!),
                                  if (_error != null)
                                    Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  if (_offset == 0 &&
                                      retry != null &&
                                      ['error', 'interrupted', 'cancelled']
                                          .contains(retry['request_state']))
                                    TextButton(
                                        onPressed: _sending
                                            ? null
                                            : () =>
                                                _retry(retry['id'] as String),
                                        child:
                                            const Text('Retry last request')),
                                  Wrap(children: [
                                    TextButton(
                                        onPressed:
                                            _messages.length < 100 || _sending
                                                ? null
                                                : () {
                                                    _offset += 100;
                                                    _refresh();
                                                  },
                                        child: const Text('Older messages')),
                                    TextButton(
                                        onPressed: _offset == 0 || _sending
                                            ? null
                                            : () {
                                                _offset = (_offset - 100)
                                                    .clamp(0, 1000000);
                                                _refresh();
                                              },
                                        child: const Text('Newer messages'))
                                  ]),
                                ])))),
                const Divider(),
                Expanded(
                    flex: 3,
                    child: _messages.isEmpty
                        ? const SingleChildScrollView(
                            child: EmptyState(
                                icon: Icons.chat_bubble_outline,
                                title: 'Start a conversation',
                                message:
                                    'Write a message. AI replies require valid provider settings and an internet connection.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final m = _messages[index];
                              final user = m['role'] == 'user';
                              return Align(
                                  alignment: user
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                      constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.sizeOf(context).width *
                                                  0.85),
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: user
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SelectableText(
                                                m['content'] as String,
                                                onSelectionChanged: (selection,
                                                        _) =>
                                                    _selections[m['id']
                                                        as String] = selection),
                                            if (m['purpose'] == 'feedback')
                                              const Text(
                                                  'Requested feedback — not a proficiency assessment'),
                                            if (!user && m['is_local'] == 0)
                                              Wrap(spacing: 4, children: [
                                                TextButton(
                                                    onPressed: () =>
                                                        _saveWord(m),
                                                    child: const Text(
                                                        'Save vocabulary')),
                                                TextButton(
                                                    onPressed: () =>
                                                        _speakSelection(m),
                                                    child: const Text(
                                                        'Speak selection')),
                                                TextButton(
                                                    onPressed: () =>
                                                        _saveMistake(m),
                                                    child: const Text(
                                                        'Confirm correction')),
                                              ]),
                                            if (!user && m['is_local'] == 1)
                                              const Text(
                                                  'Local note — not a live model reply'),
                                            if (user &&
                                                m['request_state'] !=
                                                    'complete')
                                              Text(
                                                  'Request: ${m['request_state']}'),
                                          ])));
                            })),
                SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: _input,
                                  readOnly: _sending || _offset != 0,
                                  maxLength: 20000,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                      hintText: 'Type your message…',
                                      counterText: ''),
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send())),
                          IconButton.filled(
                              onPressed:
                                  _sending || _offset != 0 ? null : _send,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.send)),
                        ]))),
              ]));
  }
}

class _ConversationNameDialog extends StatefulWidget {
  const _ConversationNameDialog({required this.initial});
  final String initial;
  @override
  State<_ConversationNameDialog> createState() =>
      _ConversationNameDialogState();
}

class _ConversationNameDialogState extends State<_ConversationNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Conversation title'),
          content: TextField(
              controller: _controller,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Title')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (_controller.text.trim().isNotEmpty) {
                    Navigator.pop(context, _controller.text.trim());
                  }
                },
                child: const Text('Save title'))
          ]);
}

class _ConversationDialog extends StatefulWidget {
  const _ConversationDialog({required this.db});
  final AppDatabase db;
  @override
  State<_ConversationDialog> createState() => _ConversationDialogState();
}

class _ConversationDialogState extends State<_ConversationDialog> {
  List<Map<String, dynamic>>? _rows;
  String _query = '';
  int _limit = 100, _searchVersion = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_searchVersion;
    final rows =
        await widget.db.getAiConversations(search: _query, limit: _limit);
    if (mounted && version == _searchVersion) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Saved conversations'),
          content: SizedBox(
              width: 500,
              height: 400,
              child: _rows == null
                  ? const LoadingView()
                  : ListView(
                      key: const ValueKey('conversation-history-list'),
                      children: [
                          TextField(
                              decoration: const InputDecoration(
                                  labelText:
                                      'Search conversation titles or messages'),
                              onChanged: (value) {
                                _query = value;
                                _limit = 100;
                                _load();
                              }),
                          if (_rows!.length >= _limit)
                            TextButton(
                                onPressed: () {
                                  _limit += 100;
                                  _load();
                                },
                                child: const Text('Load more conversations')),
                          if (_rows!.isEmpty)
                            const Text('No matching conversations saved.'),
                          for (final c in _rows!)
                            ListTile(
                                title: Text(c['title'] as String? ??
                                    'Untitled conversation'),
                                subtitle:
                                    Text('${c['message_count']} messages'),
                                onTap: () =>
                                    Navigator.pop(context, c['id'] as String),
                                trailing: Wrap(children: [
                                  IconButton(
                                      tooltip: 'Rename conversation',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        final title = await showDialog<String>(
                                            context: context,
                                            builder: (_) =>
                                                _ConversationNameDialog(
                                                    initial:
                                                        c['title'] as String? ??
                                                            'Conversation'));
                                        if (title != null) {
                                          await widget.db.renameAiConversation(
                                              c['id'] as String, title);
                                          await _load();
                                        }
                                      }),
                                  IconButton(
                                      tooltip: 'Delete conversation',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final accepted = await showConfirmDialog(
                                            context,
                                            title: 'Delete conversation?',
                                            message:
                                                'This permanently deletes this conversation and its messages.');
                                        if (accepted == true) {
                                          await widget.db.deleteAiConversation(
                                              c['id'] as String);
                                          await _load();
                                        }
                                      }),
                                ])),
                        ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ]);
}
