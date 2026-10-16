import 'package:flutter/foundation.dart';

/// Owns the example's progress, result and error presentation.
final class DemoController extends ChangeNotifier {
  DemoController(this._runDemo);

  final Future<String> Function() _runDemo;
  bool busy = false;
  String? result;
  String? error;
  bool _closed = false;

  Future<void> run() async {
    if (busy || _closed) return;
    busy = true;
    result = null;
    error = null;
    notifyListeners();
    try {
      result = await _runDemo();
    } catch (failure) {
      error = failure.toString();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
