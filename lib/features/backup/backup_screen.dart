import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/backup/backup_service.dart';
import '../../core/services/maintenance_controller.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/widgets/common_widgets.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool _recovery = false;
  String? _last;
  String? _message;
  BackupService? _service;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final docs = await getApplicationDocumentsDirectory();
      final service = BackupService(db, docs);
      final rows = (await db.db)
          .select('SELECT last_success_at FROM backup_metadata WHERE id=1');
      final recovery = await service.hasRecovery();
      if (mounted)
        setState(() {
          _service = service;
          _recovery = recovery;
          _last =
              rows.isEmpty ? null : rows.single['last_success_at'] as String;
        });
    } catch (_) {
      if (mounted)
        setState(() =>
            _message = 'Could not access local backup storage. Please retry.');
    }
  }

  void _progress(String value) {
    if (mounted) setState(() => _message = value);
  }

  Future<void> _create() async {
    if (_busy || _service == null) return;
    setState(() => _busy = true);
    File? archive;
    try {
      final temp = await getTemporaryDirectory();
      archive = File(p.join(temp.path, 'lexiflow-${newId()}.lexiflowbackup'));
      await _service!.create(archive, progress: _progress);
      _progress('Choose where to save the verified backup…');
      final hash = await BackupService.checksum(archive);
      final saved = await const MethodChannel('lexiflow/backup')
          .invokeMethod<bool>('saveBackup', {
        'path': archive.path,
        'sha256': hash,
        'name':
            'LexiFlow-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.lexiflowbackup',
      });
      if (saved == true) {
        try {
          await _service!.recordSavedBackup();
          _progress('Backup saved and verified. Keep it somewhere safe.');
        } catch (_) {
          _progress(
              'Backup saved and verified, but its date could not be recorded.');
        }
        await _load();
      } else {
        _progress('Save cancelled. No successful backup was recorded.');
      }
    } catch (e) {
      _progress(e is BackupFailure
          ? e.message
          : 'Backup could not be saved and verified. Check storage and file access.');
    } finally {
      try {
        if (archive != null && await archive.exists()) await archive.delete();
      } catch (_) {/* Temporary cache cleanup must not hide the save result. */}
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore({bool recovery = false}) async {
    if (_busy || _service == null) return;
    setState(() => _busy = true);
    try {
      File? archive;
      if (!recovery) {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.any, allowMultiple: false, withData: false);
        if (result == null) return;
        final path = result.files.single.path;
        if (path == null)
          throw const BackupFailure('The selected document is not readable.');
        archive = File(path);
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(recovery
                    ? 'Recover previous learning data?'
                    : 'Replace current learning data?'),
                content: const Text(
                    'Your current learning records and plan will be replaced. A recovery copy of the current database will be kept, and existing media will be retained. AI keys stay on this device. Do not close the app during restore.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Replace and restore'))
                ],
              ));
      if (confirmed != true || !mounted) return;
      final sessions = ref.read(studySessionServiceProvider);
      await sessions.finish(interrupted: true);
      if (!mounted) return;
      final maintenance = ref.read(maintenanceControllerProvider);
      final service = _service!;
      // Capture dependencies before this route unmounts.
      await maintenance.run(() async {
        if (recovery) {
          await service.recoverPrevious();
        } else {
          await service.restore(archive!, progress: maintenance.progress);
        }
      });
    } catch (e) {
      _progress(e is BackupFailure
          ? e.message
          : 'Could not begin restore. No learning data was replaced.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
            appBar: AppBar(title: const Text('Backup & Restore')),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              const Text('Your learning, protected offline',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                  'Back up learning records, articles, books, audio and recordings. API keys, credentials and caches are excluded. The archive is not encrypted; store it privately.'),
              const SizedBox(height: 16),
              LexiCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(_last == null
                        ? 'No successful backup recorded yet'
                        : 'Last successful backup: ${DateFormat.yMMMd().add_jm().format(DateTime.parse(_last!).toLocal())}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        onPressed: _busy || _service == null ? null : _create,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Create Backup')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: _busy || _service == null ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore Backup')),
                    if (_recovery)
                      TextButton(
                          onPressed:
                              _busy ? null : () => _restore(recovery: true),
                          child: const Text('Recover previous installation')),
                  ])),
              if (_busy)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator()),
              if (_message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(_message!))),
              if (_service == null)
                TextButton(onPressed: _load, child: const Text('Retry')),
              const SizedBox(height: 16),
              const Text(
                  'Backups support up to 512 MiB total and 256 MiB per file. Extra free storage is required for validation and recovery. Older media copies remain on this device after restore so recovery stays possible.'),
            ])),
      );
}
