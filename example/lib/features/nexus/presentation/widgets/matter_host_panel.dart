// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'package:flutter/material.dart';

abstract interface class MatterDeviceSession {
  Future<void> setOnOff(bool on);
  Future<bool> readOnOff();
  Future<void> close();
}

class MatterHostModel extends ChangeNotifier {
  MatterHostModel(this.open);
  final Future<MatterDeviceSession> Function(String value, bool commission)
  open;
  MatterDeviceSession? _session;
  bool busy = false;
  bool? on;
  String? error;
  bool _disposed = false;
  Future<void>? _pending;
  bool get connected => _session != null;

  Future<void> _run(Future<void> Function() action) {
    if (busy || _disposed) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    return _pending = Future<void>.sync(action)
        .catchError((Object failure) {
          on = null;
          error = failure.toString();
        })
        .whenComplete(() {
          busy = false;
          if (!_disposed) notifyListeners();
        });
  }

  Future<void> connect(String value, bool commission) => _run(() async {
    if (_session != null) return;
    _session = await open(value.trim(), commission);
    on = await _session!.readOnOff();
  });

  Future<void> set(bool value) => _run(() async {
    on = null;
    await _session!.setOnOff(value);
    on = await _session!.readOnOff();
    if (on != value) {
      throw StateError('Device readback did not match the command.');
    }
  });

  Future<void> refresh() => _run(() async {
    on = await _session!.readOnOff();
  });

  Future<void> disconnect() => _run(() async {
    final session = _session;
    _session = null;
    on = null;
    await session?.close();
  });

  @override
  void dispose() {
    _disposed = true;
    // Finish admitted work before closing; no callback calls notify after dispose.
    unawaited(
      (_pending ?? Future<void>.value()).then((_) async {
        final session = _session;
        _session = null;
        try {
          await session?.close();
        } catch (_) {
          /* Explicit disconnect reports errors in UI. */
        }
      }),
    );
    super.dispose();
  }
}

class MatterHostPanel extends StatefulWidget {
  const MatterHostPanel({
    super.key,
    required this.model,
    required this.backend,
    required this.inputLabel,
    required this.android,
    this.initialValue = '',
  });
  final MatterHostModel model;
  final String backend;
  final String inputLabel;
  final bool android;
  final String initialValue;
  @override
  State<MatterHostPanel> createState() => _MatterHostPanelState();
}

class _MatterHostPanelState extends State<MatterHostPanel> {
  late final _input = TextEditingController(text: widget.initialValue);
  bool _consent = false;
  bool _commission = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final enabled = model.connected && !model.busy;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Matter devices',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(widget.backend),
                    avatar: const Icon(Icons.hub_outlined),
                  ),
                  const Text(
                    'Qualification only · software light, endpoint 1. No physical-product provisioning.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _input,
                    enabled: !model.busy && !model.connected,
                    decoration: InputDecoration(
                      labelText: widget.inputLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (widget.android)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Commission a fresh test light'),
                      subtitle: const Text(
                        'Changes the example app’s test fabric. Leave off to restore an existing pairing.',
                      ),
                      value: _commission,
                      onChanged: model.busy || model.connected
                          ? null
                          : (v) => setState(() => _commission = v!),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    title: Text(
                      widget.android
                          ? 'Allow commands to my test light'
                          : 'I verified this local runtime bundle',
                    ),
                    onChanged: model.busy || model.connected
                        ? null
                        : (v) => setState(() => _consent = v!),
                  ),
                  FilledButton.icon(
                    onPressed: model.busy || model.connected || !_consent
                        ? null
                        : () => model.connect(_input.text, _commission),
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.connected
                        ? 'Software light connected'
                        : 'Not connected',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    model.on == null
                        ? 'Device state: unknown'
                        : model.on!
                        ? 'Device state: On'
                        : 'Device state: Off',
                  ),
                  const Text(
                    'State is read from the device, not inferred from a button press.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: enabled ? () => model.set(true) : null,
                        child: const Text('Turn on'),
                      ),
                      OutlinedButton(
                        onPressed: enabled ? () => model.set(false) : null,
                        child: const Text('Turn off'),
                      ),
                      OutlinedButton(
                        onPressed: enabled ? model.refresh : null,
                        child: const Text('Refresh state'),
                      ),
                      TextButton(
                        onPressed: enabled ? model.disconnect : null,
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                  if (model.busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (model.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SelectableText(
                        'Matter operation failed: ${model.error}\nIf the light disappeared, restart it and explicitly commission the new fixture. Native host failures may require an app process restart.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
