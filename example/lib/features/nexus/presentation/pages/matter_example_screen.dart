// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MatterExampleScreen extends StatefulWidget {
  const MatterExampleScreen({super.key, this.openController});

  final Future<OmnixMatterController> Function()? openController;

  @override
  State<MatterExampleScreen> createState() => _MatterExampleScreenState();
}

class _MatterExampleScreenState extends State<MatterExampleScreen>
    with WidgetsBindingObserver {
  late final _model = _MatterViewModel(widget.openController);
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _passcode = TextEditingController(text: '20202021');
  final _name = TextEditingController(text: 'Software light');
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) _model.lifecycleChanged(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _model.lifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    _address.dispose();
    _passcode.dispose();
    _name.dispose();
    super.dispose();
  }

  void _pair() {
    if (!_consent || !_model.canCommand || !_form.currentState!.validate()) {
      return;
    }
    unawaited(
      _model.pair(
        _address.text.trim(),
        int.parse(_passcode.text.trim()),
        _name.text.trim(),
      ),
    );
  }

  String? _validateAddress(String? value) {
    var address = (value ?? '').trim();
    if (address.startsWith('[')) {
      final socket = RegExp(r'^\[([^\]]+)\]:(\d{1,5})$').firstMatch(address);
      final port = socket == null ? null : int.tryParse(socket.group(2)!);
      if (socket == null || port == null || port < 1 || port > 65535) {
        return 'Enter an IPv6 endpoint such as [::1]:5540.';
      }
      address = socket.group(1)!;
    }
    final parts = address.split('%');
    if (parts.length > 2 ||
        (parts.length == 2 &&
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(parts.last))) {
      return 'Enter an IPv6 address with an optional %interface scope.';
    }
    try {
      Uri.parseIPv6Address(parts.first);
      return null;
    } on FormatException {
      return 'Enter a literal IPv6 address, for example ::1.';
    }
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _button(String label, String operation, VoidCallback? action) {
    return OutlinedButton.icon(
      onPressed: action,
      icon: _model.busy == operation
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.science_outlined, size: 18),
      label: Text(label),
    );
  }

  Widget _device(OmnixMatterDevice device) {
    final key = _model.keyFor(device);
    final onOff = _model.onOff[key];
    final enabled = _model.canCommand && device.operational;
    return _card(device.name, [
      SelectableText('Node ${device.nodeId} · Endpoint ${device.endpoint}'),
      const SizedBox(height: 8),
      Text(
        !device.operational
            ? 'Incomplete pairing — device is not operational. Reload to check.'
            : onOff == null
            ? 'On/off: unknown — read to check.'
            : 'Last read: ${onOff ? 'on' : 'off'}',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _button(
            'Read on/off',
            'read:$key',
            enabled ? () => unawaited(_model.read(device)) : null,
          ),
          _button(
            'Turn on',
            'on:$key',
            enabled ? () => unawaited(_model.set(device, true)) : null,
          ),
          _button(
            'Turn off',
            'off:$key',
            enabled ? () => unawaited(_model.set(device, false)) : null,
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card('Matter · experimental simulator only', [
                      Text(
                        'Disposable software lights only.',
                        style: TextStyle(color: colors.primary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Production attestation is not supported. '
                        'Do not pair real devices. Start the controller explicitly '
                        'to use this experiment.',
                      ),
                    ]),
                    _card('Controller', [
                      Text(_model.controllerStatus),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _button(
                            'Start Controller',
                            'start',
                            _model.canStart
                                ? () => unawaited(_model.start())
                                : null,
                          ),
                          _button(
                            'Reload devices',
                            'reload',
                            _model.canCommand
                                ? () => unawaited(_model.reload())
                                : null,
                          ),
                          _button(
                            'Stop Controller',
                            'stop',
                            _model.canStop
                                ? () => unawaited(_model.stop())
                                : null,
                          ),
                        ],
                      ),
                    ]),
                    if (_model.error != null)
                      Card(
                        color: colors.errorContainer,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Semantics(
                            liveRegion: true,
                            child: SelectableText(
                              _model.error!,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                        ),
                      ),
                    if (_model.message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_model.message!),
                        ),
                      ),
                    _card('Pair software light', [
                      Form(
                        key: _form,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _address,
                              enabled: _model.canCommand,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'IPv6 address',
                                hintText:
                                    '::1, [::1]:5540 or fe80::1234%interface',
                              ),
                              validator: _validateAddress,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passcode,
                              enabled: _model.canCommand,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Passcode',
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                final code = int.tryParse(text);
                                return !RegExp(r'^\d{1,8}$').hasMatch(text) ||
                                        code == null ||
                                        code < 1
                                    ? 'Enter a positive passcode of up to eight digits.'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _name,
                              enabled: _model.canCommand,
                              decoration: const InputDecoration(
                                labelText: 'Light name',
                              ),
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Enter a name for the simulator.'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _consent,
                              title: const Text(
                                'I am connecting a disposable simulator, not a real device',
                              ),
                              onChanged: _model.canCommand
                                  ? (value) => setState(
                                      () => _consent = value ?? false,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _button(
                        'Pair software light',
                        'pair',
                        _model.canCommand && _consent ? _pair : null,
                      ),
                    ]),
                    if (_model.devices.isEmpty)
                      _card('Devices', [
                        Text(
                          _model.isOpen
                              ? 'No devices loaded. Reload devices or pair a simulator.'
                              : 'Start the controller to load simulator devices.',
                        ),
                      ]),
                    ..._model.devices.map(_device),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Serializes native operations; shutdown drains the active operation before
// closing, so no device command can race with a closed controller.
class _MatterViewModel extends ChangeNotifier {
  _MatterViewModel(this._openController);

  final Future<OmnixMatterController> Function()? _openController;
  static const _network = MethodChannel(
    'xyz.omniecosystem.omnix/matter_network',
  );
  OmnixMatterController? _controller;
  Future<void>? _pending;
  Future<void>? _closing;
  bool _networkHeld = false;
  bool _paused = false;
  bool _disposed = false;
  bool _stopping = false;
  bool _closeFailed = false;
  String? busy;
  String? error;
  String? message;
  List<OmnixMatterDevice> devices = [];
  final Map<String, bool> onOff = {};

  bool get isOpen => _controller != null && !_stopping && !_closeFailed;
  bool get canStart =>
      !_disposed &&
      !_paused &&
      !_networkHeld &&
      _controller == null &&
      busy == null &&
      !_stopping;
  bool get canCommand => !_disposed && !_paused && isOpen && busy == null;
  bool get canStop =>
      !_disposed &&
      !_stopping &&
      (_controller != null || _networkHeld || busy == 'start');
  String get controllerStatus => _stopping
      ? 'Stopping controller…'
      : _closeFailed
      ? 'Shutdown failed. Retry Stop Controller before starting again.'
      : isOpen
      ? 'Controller open.'
      : busy == 'start'
      ? 'Starting controller…'
      : 'Controller stopped.';

  String keyFor(OmnixMatterDevice device) =>
      '${device.nodeId}:${device.endpoint}';

  void lifecycleChanged(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      _notify();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _paused = true;
      unawaited(stop());
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(String operation, Future<void> Function() action) {
    if (_disposed || _stopping || busy != null) return Future.value();
    busy = operation;
    error = null;
    message = null;
    _notify();
    final pending = _execute(operation, action);
    _pending = pending;
    return pending;
  }

  Future<void> _execute(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (exception) {
      if (!_disposed) error = '$operation failed: $exception';
    } finally {
      busy = null;
      _notify();
    }
  }

  Future<void> start() {
    if (!canStart) return Future.value();
    return _run('start', () async {
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          // Track even a failed acquire response, so cleanup can release a
          // lock that the host may already have acquired.
          _networkHeld = true;
          await _network.invokeMethod<void>('acquire');
        }
        if (_disposed || _stopping || _paused) return;
        final opener = _openController;
        if (opener != null) {
          _controller = await opener();
        } else {
          final support = await getApplicationSupportDirectory();
          if (_disposed || _stopping || _paused) return;
          _controller = await OmnixMatterController.open(
            directory: path.join(support.path, 'omnix-matter-simulator'),
          );
        }
        // Stop/dispose drains this operation before closing its handle.
        if (!_disposed && !_stopping && !_paused) {
          _closeFailed = false;
          message =
              'Controller started. Reload devices to inspect saved simulators.';
        }
      } catch (exception) {
        try {
          await _releaseNetwork();
        } catch (releaseError) {
          _closeFailed = true;
          throw StateError('$exception; network release failed: $releaseError');
        }
        rethrow;
      }
    });
  }

  Future<void> reload() {
    if (!canCommand) return Future.value();
    final controller = _controller!;
    return _run('reload', () async {
      final loaded = await controller.devices();
      if (_disposed || _stopping) return;
      devices = List.of(loaded);
      onOff.clear();
      message = '${devices.length} simulator device(s) loaded.';
    });
  }

  Future<void> pair(String address, int passcode, String name) {
    if (!canCommand) return Future.value();
    final controller = _controller!;
    return _run('pair', () async {
      final device = await controller.commissionSimulator(
        address: address,
        passcode: passcode,
        name: name,
        simulatorConsent: true,
      );
      if (_disposed || _stopping) return;
      devices = [
        ...devices.where((existing) => keyFor(existing) != keyFor(device)),
        device,
      ];
      onOff.remove(keyFor(device));
      message = device.operational
          ? 'Paired ${device.name}. Read on/off to check its state.'
          : 'Incomplete pairing for ${device.name}. Reload devices to check progress.';
    });
  }

  Future<void> read(OmnixMatterDevice device) {
    if (!canCommand || !device.operational) return Future.value();
    final controller = _controller!;
    return _run('read:${keyFor(device)}', () async {
      onOff.remove(keyFor(device));
      final value = await controller.readOnOff(device);
      if (_disposed || _stopping) return;
      onOff[keyFor(device)] = value;
      message = '${device.name} reports ${value ? 'on' : 'off'}.';
    });
  }

  Future<void> set(OmnixMatterDevice device, bool value) {
    if (!canCommand || !device.operational) return Future.value();
    final controller = _controller!;
    return _run('${value ? 'on' : 'off'}:${keyFor(device)}', () async {
      onOff.remove(keyFor(device));
      await controller.setOnOff(device, value);
      if (_disposed || _stopping) return;
      message =
          'Sent turn ${value ? 'on' : 'off'} to ${device.name}. Read to confirm.';
    });
  }

  Future<void> stop() async {
    if (!canStop) return;
    _stopping = true;
    error = null;
    message = null;
    _notify();
    await _pending;
    if (_disposed) return; // Disposal owns shutdown from this point.
    busy = 'stop';
    _notify();
    try {
      await _closeController();
      _closeFailed = false;
      devices = [];
      onOff.clear();
      message = 'Controller stopped.';
    } catch (exception) {
      _closeFailed = true;
      error = 'Stop Controller failed: $exception';
    } finally {
      busy = null;
      _stopping = false;
      _notify();
    }
  }

  Future<void> _disposeController() async {
    await _pending;
    try {
      await _closeController();
    } catch (exception) {
      // There is no mounted UI left in which to display cleanup errors.
      debugPrint('Matter simulator controller cleanup failed: $exception');
    }
  }

  Future<void> _closeController() {
    // Stop and dispose share both native close and network release.
    return _closing ??= _finishShutdown().whenComplete(() => _closing = null);
  }

  Future<void> _finishShutdown() async {
    try {
      await _controller?.close();
      _controller = null;
    } finally {
      await _releaseNetwork();
    }
  }

  Future<void> _releaseNetwork() async {
    if (!_networkHeld) return;
    await _network.invokeMethod<void>('release');
    _networkHeld = false;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_disposeController());
    super.dispose();
  }
}
