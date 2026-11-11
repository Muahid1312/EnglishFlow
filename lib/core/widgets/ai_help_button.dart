import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_teacher_service.dart';
import '../services/providers.dart';
import 'common_widgets.dart';

class AiHelpButton extends ConsumerStatefulWidget {
  const AiHelpButton(
      {super.key,
      required this.task,
      required this.content,
      this.label = 'Ask AI',
      this.onResponse,
      this.beforeSend});
  final AiTask task;
  final String Function() content;
  final String label;
  final Future<void> Function(String, String)? onResponse;
  final Future<bool> Function()? beforeSend;
  @override
  ConsumerState<AiHelpButton> createState() => _AiHelpButtonState();
}

class _AiHelpButtonState extends ConsumerState<AiHelpButton> {
  bool _busy = false, _waiting = false;
  Future<void> _request() async {
    if (_busy) return;
    final service = ref.read(aiTeacherServiceProvider);
    final timer = ref.read(studySessionServiceProvider);
    setState(() => _busy = true);
    try {
      if (widget.beforeSend != null && !await widget.beforeSend!()) return;
      final status = await service.checkStatus();
      if (!mounted) return;
      if (!status.isReady) {
        throw AiFailure(AiError.notConfigured,
            status.message ?? 'Configure AI in Settings first.');
      }
      final configuration = await service.getConfiguration();
      final text = widget.content();
      if (text.trim().isEmpty) {
        throw const AiFailure(AiError.rejected, 'There is no text to send.');
      }
      if (!mounted) return;
      final accepted = await showConfirmDialog(context,
          title: 'Send text to AI?',
          message:
              'This sends the selected text to ${configuration.provider.name} (${configuration.model}). It may include private writing or imported content. Audio and files are not uploaded. Continue?',
          confirmLabel: 'Send text');
      if (accepted != true) return;
      if (mounted) setState(() => _waiting = true);
      final response = await timer.withoutAiWaitingTime(
          () => service.complete([AiMessage('user', text)], task: widget.task));
      await widget.onResponse?.call(response, text);
      if (mounted) setState(() => _waiting = false);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) =>
              AlertDialog(
                  title: const Text('AI response'),
                  content:
                      SingleChildScrollView(child: SelectableText(response)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'))
                  ]));
    } on AiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.retryAfter == null
                ? error.message
                : '${error.message} Retry after ${error.retryAfter!.inSeconds} seconds.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not complete AI assistance. Your local text is unchanged.')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waiting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: _busy ? null : _request,
      icon: _waiting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome),
      label: Text(_waiting ? 'Waiting for AI…' : widget.label));
}
