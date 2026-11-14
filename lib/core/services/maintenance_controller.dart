import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backup/backup_service.dart';

/// Lives above the router. Replacing the router with maintenance UI disposes
/// learning screens before database replacement, preventing stale editors from
/// writing into restored records. Operations continue if their caller unmounts.
class MaintenanceController extends ChangeNotifier {
  bool active = false;
  bool done = false;
  bool failed = false;
  String message = '';

  void progress(String value) {
    message = value;
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (active) return;
    active = true;
    done = false;
    failed = false;
    message = 'Preparing a safe restore…';
    notifyListeners();
    // Ensure all old learning pages have actually been disposed first.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await action();
      message = 'Restore complete. Your learning progress will be reloaded.';
    } catch (error) {
      failed = true;
      message = error is BackupFailure
          ? error.message
          : 'Restore did not complete. A recovery copy is retained if replacement began. Return to learning to reopen or recover the database.';
    } finally {
      done = true;
      notifyListeners();
    }
  }

  void leave() {
    if (!done) return;
    active = false;
    notifyListeners();
  }
}

final maintenanceControllerProvider =
    ChangeNotifierProvider<MaintenanceController>(
        (ref) => MaintenanceController());
