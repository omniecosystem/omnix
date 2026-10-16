// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:omnix_example/features/nexus/presentation/widgets/matter_host_panel.dart';

class MatterHostScreen extends StatefulWidget {
  const MatterHostScreen({super.key});
  @override
  State<MatterHostScreen> createState() => _MatterHostScreenState();
}

class _MatterHostScreenState extends State<MatterHostScreen> {
  late final model = MatterHostModel(_open);
  static const channel = MethodChannel('xyz.omniecosystem.omnix/matter_host');
  Future<MatterDeviceSession> _open(String value, bool commission) async {
    OmnixMatterHost host;
    if (Platform.isWindows) {
      if (value.isEmpty) {
        throw ArgumentError('Choose the verified runtime bundle directory.');
      }
      final temporary = await getTemporaryDirectory();
      final storage = await temporary.createTemp('matter-fixture-');
      host = await OmnixMatterHost.openWindowsFixture(
        bundle: value,
        storage: storage.path,
      );
    } else if (Platform.isAndroid) {
      if (commission) {
        if (InternetAddress.tryParse(value) == null) {
          throw ArgumentError('Enter the laptop’s literal LAN IP.');
        }
        await channel.invokeMethod<void>('commissionFixture', {
          'address': value,
        });
      }
      await channel.invokeMethod<void>('register');
      host = await OmnixMatterHost.openAndroid(
        nodeId: BigInt.from(0x12344321),
        endpoint: 1,
      );
    } else {
      throw UnsupportedError(
        'Qualified host controls are currently available on Windows and Android only.',
      );
    }
    return _Session(host);
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MatterHostPanel(
    model: model,
    backend: Platform.isAndroid
        ? 'Android · C++ SDK / JNI'
        : Platform.isWindows
        ? 'Windows · Matter.js'
        : 'Unsupported host',
    android: Platform.isAndroid,
    inputLabel: Platform.isAndroid
        ? 'Software-light laptop LAN IP (for commissioning)'
        : 'Verified runtime bundle directory',
    initialValue: const String.fromEnvironment('OMNIX_MATTER_BUNDLE'),
  );
}

class _Session implements MatterDeviceSession {
  _Session(this.host);
  final OmnixMatterHost host;
  @override
  Future<void> setOnOff(bool on) => host.setOnOff(on: on);
  @override
  Future<bool> readOnOff() => host.readOnOff();
  @override
  Future<void> close() => host.close();
}
