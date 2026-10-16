import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:omnix/omnix.dart';
import '../widgets/tool_approval_dialog.dart';

final exampleNavigatorKey = GlobalKey<NavigatorState>();
final exampleToolApproval = ExampleToolApproval();

class ExampleToolApproval with WidgetsBindingObserver {
  Completer<bool>? _pending;
  DialogRoute<bool>? _route;
  NavigatorState? _navigator;

  Future<bool> approve(OmnixToolRequest request, {String? details}) async {
    final navigator = exampleNavigatorKey.currentState;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_pending != null ||
        navigator == null ||
        !navigator.mounted ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return false;
    }
    final pending = Completer<bool>();
    _pending = pending;
    _navigator = navigator;
    WidgetsBinding.instance.addObserver(this);
    final route = DialogRoute<bool>(
      context: navigator.context,
      builder: (_) => ToolApprovalDialog(
        toolName: request.toolName,
        arguments:
            details ??
            const JsonEncoder.withIndent('  ').convert(request.arguments),
        onAllow: () => cancel(approved: true),
        onDeny: cancel,
      ),
    );
    _route = route;
    final timer = Timer(const Duration(seconds: 20), cancel);
    unawaited(
      navigator.push(route).then((_) {
        if (identical(_pending, pending)) cancel();
      }),
    );
    try {
      return await pending.future;
    } finally {
      timer.cancel();
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  void cancel({bool approved = false}) {
    final pending = _pending;
    final route = _route;
    final navigator = _navigator;
    _pending = null;
    _route = null;
    _navigator = null;
    if (route != null &&
        route.isActive &&
        navigator != null &&
        navigator.mounted) {
      navigator.removeRoute(route);
    }
    if (pending != null && !pending.isCompleted) {
      pending.complete(approved);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }
}
