// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:omnix/omnix.dart';
// The standalone demo selects the freshly built DLL explicitly. Applications
// should use the normal Flutter Native Asset initialization instead.
// ignore: implementation_imports
import 'package:omnix/src/rust/frb_generated.dart' show RustLib;
import 'package:omnix_example/public_knowledge_demo.dart';

const nexusDeviceUsage = '''
Run from omnix/example with OMNIX_NATIVE_DLL set to the built Rust library.

  dart run bin/nexus_device.dart show
  dart run bin/nexus_device.dart init
  dart run bin/nexus_device.dart allow --peer-key <other-public-key>
  dart run bin/nexus_device.dart deny --peer-key <other-public-key>
  dart run bin/nexus_device.dart serve --origin <this-node-https-url> --fixture <json-file>
  dart run bin/nexus_device.dart ask --origin <peer-https-url> --question <text>

Set OMNIXUS_NODE_DIR to this node's private identity directory, or pass
--node-dir <directory>. Serve defaults to port 46137 and
public_knowledge.json. Use Ctrl+C to stop the listener.
''';

/// Validated, testable inputs for one node-demo command.
final class NexusDeviceOptions {
  const NexusDeviceOptions({
    required this.command,
    required this.nodeDirectory,
    required this.origin,
    required this.fixture,
    required this.question,
    required this.peerKey,
    required this.port,
  });

  final String command;
  final String nodeDirectory;
  final String? origin;
  final String fixture;
  final String? question;
  final String? peerKey;
  final int port;
}

NexusDeviceOptions parseNexusDeviceOptions(
  List<String> arguments, {
  Map<String, String>? environment,
}) {
  if (arguments.isEmpty ||
      !{
        'init',
        'show',
        'allow',
        'deny',
        'serve',
        'ask',
      }.contains(arguments.first)) {
    throw const FormatException(
      'Expected init, show, allow, deny, serve, or ask',
    );
  }
  final env = environment ?? Platform.environment;
  final parser = ArgParser()
    ..addOption('node-dir')
    ..addOption('origin')
    ..addOption('fixture', defaultsTo: 'public_knowledge.json')
    ..addOption('question')
    ..addOption('peer-key')
    ..addOption('port', defaultsTo: '46137');
  final parsed = parser.parse(arguments.skip(1).toList());
  if (parsed.rest.isNotEmpty) {
    throw const FormatException('Unexpected positional arguments');
  }
  final command = arguments.first;
  final nodeDirectory = parsed.option('node-dir') ?? env['OMNIXUS_NODE_DIR'];
  if (nodeDirectory == null || nodeDirectory.trim().isEmpty) {
    throw const FormatException('Set OMNIXUS_NODE_DIR or pass --node-dir');
  }
  final origin =
      parsed.option('origin') ??
      env[command == 'serve' ? 'OMNIXUS_DEMO_PUBLIC_URL' : 'OMNIXUS_DEMO_URL'];
  if ((command == 'serve' || command == 'ask') &&
      (origin == null || origin.trim().isEmpty)) {
    throw const FormatException(
      'Pass --origin or set the matching URL variable',
    );
  }
  final question = parsed.option('question');
  if (command == 'ask' && (question == null || question.trim().isEmpty)) {
    throw const FormatException('Pass a nonempty --question');
  }
  final peerKey = parsed.option('peer-key');
  if ((command == 'allow' || command == 'deny') &&
      (peerKey == null || peerKey.trim().isEmpty)) {
    throw const FormatException('Pass --peer-key');
  }
  final port = int.tryParse(parsed.option('port') ?? '');
  if (port == null || port < 1 || port > 65535) {
    throw const FormatException('--port must be between 1 and 65535');
  }
  return NexusDeviceOptions(
    command: command,
    nodeDirectory: nodeDirectory,
    origin: origin,
    fixture: parsed.option('fixture')!,
    question: question,
    peerKey: peerKey,
    port: port,
  );
}

/// Runs one interactive public-Knowledge demo operation.
Future<int> runNexusDeviceDemo(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.write(nexusDeviceUsage);
    return 0;
  }
  late final NexusDeviceOptions options;
  try {
    options = parseNexusDeviceOptions(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.write(nexusDeviceUsage);
    return 64;
  }

  var rustInitialized = false;
  try {
    final dll = Platform.environment['OMNIX_NATIVE_DLL'];
    if (dll == null || dll.trim().isEmpty) {
      throw StateError('Set OMNIX_NATIVE_DLL to the built Omnix Rust library');
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(dll));
    rustInitialized = true;
    final node = OmnixNexusNode(nodeDirectory: options.nodeDirectory);
    switch (options.command) {
      case 'init':
        stdout.writeln('Node public key: ${await node.createIdentity()}');
      case 'show':
        stdout.writeln('Node public key: ${await node.publicKey()}');
      case 'allow':
        await node.allowPublicPeer(options.peerKey!);
        stdout.writeln('Granted public Knowledge to ${options.peerKey}');
      case 'deny':
        await node.denyPublicPeer(options.peerKey!);
        stdout.writeln('Revoked public Knowledge; restart serve to apply');
      case 'serve':
        final knowledge = await publicDemoKnowledge(File(options.fixture));
        final listener = await node.startPublicKnowledgeListener(
          advertisedOrigin: options.origin!,
          knowledge: knowledge,
          port: options.port,
        );
        try {
          stdout.writeln(
            'Indexed ${options.fixture} into this node\'s Knowledge.',
          );
          stdout.writeln('A2A listener: 127.0.0.1:${listener.port}');
          stdout.writeln('Advertised origin: ${options.origin}');
          stdout.writeln('Public Knowledge only. Press Ctrl+C to stop.');
          await _waitForShutdown();
        } finally {
          await listener.stop();
        }
      case 'ask':
        final reply = await node.queryPublicKnowledge(
          options.origin!,
          options.question!,
        );
        if (reply.texts.isEmpty) {
          throw StateError('Peer returned no text artifact');
        }
        for (final text in reply.texts) {
          stdout.writeln(text);
        }
    }
    return 0;
  } catch (error) {
    stderr.writeln('Nexus demo failed: $error');
    return 70;
  } finally {
    if (rustInitialized) RustLib.dispose();
  }
}

Future<void> _waitForShutdown() async {
  final stopped = Completer<void>();
  void stop(ProcessSignal _) {
    if (!stopped.isCompleted) stopped.complete();
  }

  final interrupt = ProcessSignal.sigint.watch().listen(stop);
  final terminate = Platform.isWindows
      ? null
      : ProcessSignal.sigterm.watch().listen(stop);
  try {
    await stopped.future;
  } finally {
    await interrupt.cancel();
    await terminate?.cancel();
  }
}
