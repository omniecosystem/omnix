import 'dart:convert';

/// Host-selected limits for Rust-owned cold-load and inference admission.
///
/// These limits do not bound model memory or promise parallel native execution.
/// Queueing is disabled unless [maxWaiting] and [wait] are both positive.
final class OmnixExecutionOptions {
  const OmnixExecutionOptions({
    this.maxActive = 1,
    this.maxWaiting = 0,
    this.wait = Duration.zero,
  });

  final int maxActive;
  final int maxWaiting;
  final Duration wait;

  /// Validates and encodes the native admission configuration.
  String encode() {
    if (maxActive < 1 ||
        maxActive > 16 ||
        maxWaiting < 0 ||
        maxWaiting > 256 ||
        wait.isNegative ||
        wait > const Duration(minutes: 5) ||
        wait.inMicroseconds % 1000 != 0 ||
        (maxWaiting == 0) != (wait == Duration.zero)) {
      throw ArgumentError('Invalid execution admission limits.');
    }
    return jsonEncode({
      'maxActive': maxActive,
      'maxWaiting': maxWaiting,
      'waitMilliseconds': wait.inMilliseconds,
    });
  }
}

/// Actual cold loads and inference calls admitted or waiting at one point in time.
///
/// An admitted call may wait in a runtime's own serialized worker. This is not
/// GPU utilization, a token estimate or a count of all host work.
final class OmnixExecutionSnapshot {
  const OmnixExecutionSnapshot({required this.active, required this.waiting});
  final int active;
  final int waiting;

  /// Decodes the native counter envelope without estimating missing values.
  static OmnixExecutionSnapshot decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['active'] is! int ||
        value['waiting'] is! int ||
        (value['active'] as int) < 0 ||
        (value['waiting'] as int) < 0) {
      throw const FormatException('Invalid execution snapshot.');
    }
    return OmnixExecutionSnapshot(
      active: value['active'] as int,
      waiting: value['waiting'] as int,
    );
  }
}

/// A native admission failure, not evidence of a completed action.
enum OmnixExecutionFailure { busy, queueFull, timedOut, cancelled, unavailable }

/// An explicit native execution admission failure exposed to the host.
final class OmnixExecutionException implements Exception {
  const OmnixExecutionException(this.failure);
  final OmnixExecutionFailure failure;

  /// Recognizes only native diagnostic codes, preserving unrelated failures.
  static OmnixExecutionException? fromNative(Object error) {
    if (error is OmnixExecutionException) return error;
    final codes = <String, OmnixExecutionFailure>{
      'execution-busy': OmnixExecutionFailure.busy,
      'execution-queue-full': OmnixExecutionFailure.queueFull,
      'execution-admission-timeout': OmnixExecutionFailure.timedOut,
      'execution-admission-unavailable': OmnixExecutionFailure.unavailable,
      'generation-cancelled': OmnixExecutionFailure.cancelled,
    };
    final text = error.toString();
    for (final entry in codes.entries) {
      if (text == entry.key ||
          text.contains('BackendFailure("${entry.key}")')) {
        return OmnixExecutionException(entry.value);
      }
    }
    return null;
  }

  @override
  String toString() => 'Omnix execution: ${failure.name}';
}
