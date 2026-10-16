import 'package:flutter/foundation.dart';
import 'package:omnix/omnix.dart';
import '../../domain/workflow_backend.dart';

class WorkflowController extends ChangeNotifier {
  WorkflowController(this.backend);
  final WorkflowBackend backend;
  OmnixWorkflowProgress? progress;
  String? error;
  bool busy = false;
  bool executing = false;
  bool _disposed = false;
  bool _closing = false;
  Future<void>? _active;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _perform(
    Future<OmnixWorkflowProgress> Function() operation, {
    bool execute = false,
  }) {
    if (busy || _closing) return Future.value();
    busy = true;
    executing = execute;
    error = null;
    _changed();
    return _active = (() async {
      try {
        progress = await operation();
      } catch (e) {
        error = e.toString();
      } finally {
        busy = false;
        executing = false;
        _changed();
      }
    })();
  }

  Future<void> initialize() => _perform(backend.open);
  Future<void> newDemo() => _perform(backend.newDemo);
  Future<void> runNext() => _perform(backend.runNext, execute: true);
  Future<void> recover() => _perform(backend.recover);
  Future<void> reopen() => _perform(backend.reopen);
  Future<void> confirmSimulation() => _perform(backend.confirmSimulation);
  void cancel() {
    try {
      backend.cancel();
    } catch (e) {
      error = e.toString();
    }
    _changed();
    if (!busy) {
      _perform(backend.open);
    }
  }

  Future<void> shutdown() async {
    _closing = true;
    // Closing a feature leaves idle persisted work resumable. Active waits are cancelled.
    try {
      if (executing) backend.cancel();
    } finally {
      await _active;
      await backend.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
