import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/listening_downloads.dart';
import '../../../core/services/providers.dart';
import '../../../core/widgets/common_widgets.dart';
import 'comprehension_screen.dart';

class ListeningLibraryScreen extends ConsumerStatefulWidget {
  const ListeningLibraryScreen({super.key});
  @override ConsumerState<ListeningLibraryScreen> createState() => _ListeningLibraryScreenState();
}
class _ListeningLibraryScreenState extends ConsumerState<ListeningLibraryScreen> {
  late ListeningDownloads _downloads;
  List<Map<String,dynamic>> _lessons = [];
  bool _loading = true, _importing = false, _chosen = false, _ready = false;
  String _section = 'Discover', _statuses = '';
  String? _error, _downloadError;
  Future<int>? _usage;
  @override void initState() {
    super.initState();
    _downloads = ref.read(listeningDownloadsProvider);
    _downloads.addListener(_changed);
    _load();
  }
  Future<void> _rows() async {
    final rows = await ref.read(appDatabaseProvider).getListeningLessons();
    if (mounted) setState(() {
      _lessons = rows; _loading = false; _error = null;
      if (!_chosen && rows.any((r) => (r['audio_path'] as String).isNotEmpty)) _section = 'Downloaded Lessons';
    });
  }
  Future<void> _load() async {
    try { await _rows(); } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load listening lessons.'; });
    }
    try {
      await _downloads.initialize();
      _downloads.resumeQueue();
      if (mounted) setState(() { _ready = true; _downloadError = null; _usage = _downloads.storageBytes(); });
    } catch (_) {
      if (mounted) setState(() => _downloadError = 'Downloads could not be prepared. Your saved lessons are retained.');
    }
  }
  void _changed() {
    final status = _downloads.jobs.entries.map((e) => '${e.key}:${e.value['status']}').join('|');
    if (status == _statuses) return;
    _statuses = status;
    unawaited(_rows().catchError((Object _) {}));
    if (_ready && mounted) setState(() => _usage = _downloads.storageBytes());
  }
  Future<void> _action(Future<void> Function() action) async {
    try { await action(); if (mounted) await _rows(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error is AudioDownloadFailure ? error.message : 'Could not complete this action. Please retry.'))); }
  }
  Future<void> _import() async {
    if (_importing) return; _importing = true;
    try {
      final picked = await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:const ['mp3','m4a','wav','aac','ogg']);
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) throw const AudioDownloadFailure('The selected audio is inaccessible.');
      await _downloads.importFile(File(path),p.basenameWithoutExtension(picked.files.single.name));
      if (mounted) { setState(() { _section = 'Downloaded Lessons'; _chosen = true; }); await _rows(); }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error is AudioDownloadFailure ? error.message : 'Import failed. Check the audio and free storage.')));
    } finally { _importing = false; }
  }
  Future<void> _delete(Map<String,dynamic> lesson) async {
    final confirmed = await showConfirmDialog(context,title:'Delete offline audio?',message:'Remove this audio file from the device? Transcripts, answers, bookmarks, and study progress will stay.');
    if (confirmed == true) await _action(() => _downloads.removeAudio(lesson['id'] as String));
  }
  @override void dispose() { _downloads.removeListener(_changed); super.dispose(); }
  String _size(int bytes) => '${(bytes/(1024*1024)).toStringAsFixed(2)} MiB';
  Widget _catalogCard(Map<String,dynamic> lesson) {
    final id = lesson['id'] as String, job = _downloads.jobs[lesson['id']];
    final state = job?['status'] as String? ?? 'available';
    final received = job?['bytes_received'] as int? ?? 0;
    final total = job?['total_bytes'] as int? ?? lesson['bytes'] as int;
    final progress = total > 0 ? (received/total).clamp(0.0,1.0) : null;
    const labels = {'available':'Available','queued':'Queued','downloading':'Downloading','paused':'Paused','downloaded':'Downloaded','failed':'Failed'};
    return Card(key:ValueKey('catalog-$id'),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(lesson['title'] as String,style:Theme.of(context).textTheme.titleMedium),
      Text('${lesson['level']} target · ${lesson['accent']} · ${((lesson['duration_ms'] as int)/1000).round()} sec'),
      Text('${lesson['provider']} · ${lesson['speaker']}'),
      Text(labels[state] ?? 'Available'),
      if (['downloading','paused','failed'].contains(state) && received > 0)...[
        LinearProgressIndicator(value:progress),
        Text('${progress == null ? '' : '${(100*progress).floor()}% · '}${_size(received)} / ${_size(total)} received'),
      ],
      if (job?['error'] != null) Text(job!['error'] as String),
      Wrap(spacing:8,children:[
        if (['available','failed','paused'].contains(state)) FilledButton(onPressed:() => _action(() => _downloads.enqueue(id)),child:Text(state == 'paused' ? 'Resume' : state == 'failed' ? 'Retry download' : 'Download')),
        if (state == 'downloading' && job?['supports_resume'] == 1) TextButton(onPressed:() => _action(() => _downloads.pause(id)),child:const Text('Pause download')),
        if (['queued','downloading','paused','failed'].contains(state)) TextButton(onPressed:() => _action(() => _downloads.cancel(id)),child:const Text('Cancel download')),
        if (state == 'downloaded') FilledButton.icon(onPressed:() => context.push('/learn/listening/player/${Uri.encodeComponent(job!['lesson_id'] as String)}'),icon:const Icon(Icons.play_arrow),label:const Text('Play offline')),
      ]),
    ])));
  }
  Widget _localCard(Map<String,dynamic> lesson) {
    final path = lesson['audio_path'] as String;
    final linked = _downloads.jobs.values.where((j) => j['lesson_id'] == lesson['id']).toList();
    final hasAudio = (!(lesson['id'] as String).startsWith('download:') || _ready) && path.isNotEmpty && File(path).existsSync() && (linked.isEmpty || linked.first['status'] == 'downloaded');
    final position = lesson['last_position_ms'] as int? ?? 0, duration = lesson['duration_ms'] as int? ?? 0;
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(lesson['title'] as String,style:Theme.of(context).textTheme.titleMedium),
      Text('${lesson['difficulty']} · ${lesson['topic'] ?? 'Imported'} · ${hasAudio ? 'Local audio' : 'Audio unavailable; study records retained'}'),
      if (duration > 0) LinearProgressIndicator(value:(position/duration).clamp(0.0,1.0)),
      Wrap(spacing:8,children:[
        if (hasAudio) FilledButton.icon(onPressed:() async { await context.push('/learn/listening/player/${Uri.encodeComponent(lesson['id'] as String)}'); if (mounted) await _rows(); },icon:const Icon(Icons.play_arrow),label:const Text('Play offline')),
        TextButton(onPressed:() => Navigator.of(context).push(MaterialPageRoute<void>(builder:(_) => ComprehensionScreen(lessonId:lesson['id'] as String))),child:const Text('Transcript and comprehension')),
        if (hasAudio) TextButton.icon(onPressed:() => _delete(lesson),icon:const Icon(Icons.delete_outline),label:const Text('Delete audio')),
      ]),
    ])));
  }
  @override Widget build(BuildContext context) {
    ref.watch(listeningDownloadsProvider);
    final catalogue = _downloads.catalog;
    final active = catalogue?.lessons.where((l) => ['queued','downloading','paused','failed'].contains(_downloads.jobs[l['id']]?['status'])).toList() ?? <Map<String,dynamic>>[];
    return Scaffold(appBar:AppBar(title:const Text('Listening Studio'),actions:[IconButton(tooltip:'Import audio',onPressed:_import,icon:const Icon(Icons.file_upload_outlined))]),
      body:_loading ? const LoadingView(message:'Loading lessons…') : _error != null ? ErrorView(message:_error!,onRetry:_load) : RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('Downloads run while LexiFlow is open. Pausing is offered only after the server confirms byte-range support. Interrupted downloads can be resumed or retried here.'),
        Wrap(spacing:8,children:[for (final section in ['Discover','Downloaded Lessons','Downloads']) ChoiceChip(label:Text(section),selected:_section == section,onSelected:(_) => setState(() { _section = section; _chosen = true; }))]),
        if (_usage != null) FutureBuilder<int>(future:_usage,builder:(context,snapshot) => Row(children:[Expanded(child:Text(snapshot.hasData ? 'Managed audio: ${_size(snapshot.data!)}' : 'Checking audio storage…')),IconButton(tooltip:'Refresh storage usage',onPressed:() => setState(() => _usage = _downloads.storageBytes()),icon:const Icon(Icons.refresh))])),
        if (_downloadError != null) ErrorView(message:_downloadError!,onRetry:_load),
        if (_section == 'Downloaded Lessons')...[
          if (_lessons.isEmpty) const Text('No saved lessons yet. Download from Discover or import permitted audio.'),
          for (final lesson in _lessons) _localCard(lesson),
        ],
        if (_section == 'Downloads')...[
          if (active.isEmpty) const Text('No queued or interrupted downloads.'),
          for (final lesson in active) _catalogCard(lesson),
        ],
        if (_section == 'Discover')...[
          if (!_ready && _downloadError == null) const Text('Preparing the listening catalogue…'),
          if (_ready && catalogue != null)...[
            const Text('Original starter lessons · synthetic voices · B1/B2 curriculum targets'),
            for (final lesson in catalogue.lessons) _catalogCard(lesson),
            const Divider(),const Text('External provider resources · Online only'),
            const Text('These links open provider websites. LexiFlow does not extract or offer their audio for download.'),
            for (final provider in catalogue.providers) ListTile(title:Text(provider['name'] as String),subtitle:const Text('Online only'),trailing:TextButton(onPressed:() => _action(() async { final opened = await const MethodChannel('lexiflow/listening').invokeMethod<bool>('openOnline',{'url':provider['url']}); if (opened != true) throw const AudioDownloadFailure('No browser is available to open this provider.'); }),child:const Text('Listen Online'))),
          ],
        ],
        const SizedBox(height:16),OutlinedButton.icon(onPressed:_import,icon:const Icon(Icons.file_upload_outlined),label:const Text('Import permitted audio')),
      ])));
  }
}
