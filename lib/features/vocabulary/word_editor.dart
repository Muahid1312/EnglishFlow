import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';

class WordEditorDialog extends StatefulWidget {
  const WordEditorDialog({super.key,required this.db, this.entry,this.initialWord,this.initialContext,this.initialSource});
  final AppDatabase db;
  final Map<String, dynamic>? entry;
  final String? initialWord,initialContext,initialSource;
  @override
  State<WordEditorDialog> createState() => _WordEditorState();
}

class _WordEditorState extends State<WordEditorDialog> {
  final _word = TextEditingController();
  final _definition = TextEditingController();
  final _translation = TextEditingController();
  final _sentence = TextEditingController();
  final _extra=<String,TextEditingController>{for(final key in ['usage_example','collocations','pronunciation','personal_notes','part_of_speech']) key:TextEditingController()};
  final _source=TextEditingController(text:'Manual');
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _word.text = widget.entry?['word'] as String? ?? widget.initialWord ?? '';
    _definition.text = widget.entry?['definition'] as String? ?? '';
    _translation.text = widget.entry?['translation'] as String? ?? '';
    _sentence.text=widget.initialContext??'';
    _source.text=widget.initialSource??'Manual';
    for(final entry in _extra.entries) { entry.value.text=widget.entry?[entry.key] as String? ?? ''; }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.db.saveVocabulary(
          id: widget.entry?['id'] as String?,
          word: _word.text,
          definition: _definition.text.trim(),
          translation: _translation.text.trim(),
          sentence: _sentence.text,
          source: _source.text.trim().isEmpty?'Manual':_source.text.trim(),
          usageExample:_extra['usage_example']!.text,collocations:_extra['collocations']!.text,
          pronunciation:_extra['pronunciation']!.text,personalNotes:_extra['personal_notes']!.text,
          partOfSpeech:_extra['part_of_speech']!.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : error is ArgumentError
                ? error.message.toString()
                : 'Could not save this word.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _word.dispose();
    _definition.dispose();
    _translation.dispose();
    _sentence.dispose();
    _source.dispose();
    for(final controller in _extra.values) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.entry == null ? 'Add word' : 'Edit word'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _word,
                decoration: const InputDecoration(labelText: 'Word'),
                maxLength: 100),
            TextField(
                controller: _definition,
                decoration:
                    const InputDecoration(labelText: 'Definition (optional)')),
            TextField(
                controller: _translation,
                textDirection:TextDirection.rtl,
                decoration:
                    const InputDecoration(labelText: 'Translation (optional)')),
            TextField(
                controller: _sentence,
                decoration: const InputDecoration(
                    labelText: 'Add context sentence (optional)'),
                maxLines: 3),
            TextField(controller:_source,decoration:const InputDecoration(labelText:'Source article or book label (optional)')),
            for(final item in _extra.entries) TextField(controller:item.value,
              decoration:InputDecoration(labelText:const {'usage_example':'Example sentence','collocations':'Collocations',
                'pronunciation':'Pronunciation / IPA','personal_notes':'Personal notes','part_of_speech':'Part of speech'}[item.key])),
            if (widget.entry != null)
              const Text('Original source sentences are preserved.'),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'))
          ]);
}

