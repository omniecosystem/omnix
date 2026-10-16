// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  test('typed output bindings serialize without Dart resolution', () {
    final step = OmnixWorkflowStep(
      id: 'format',
      tool: 'host_format',
      arguments: {},
      retry: OmnixRetrySafety.safeToRepeat,
      outputBindings: {
        'utc': const OmnixWorkflowOutputBinding(
          stepId: 'read',
          pointer: '/utc',
        ),
      },
    );
    expect(step.toJson()['outputBindings'], {
      'utc': {'step': 'read', 'pointer': '/utc'},
    });
    expect(step.toJson()['input'], isEmpty);
    expect(() => step.outputBindings.clear(), throwsUnsupportedError);
  });
  test('definitions contain explicit retry contracts but no grants', () {
    final definition = OmnixWorkflowDefinition(
      id: 'job',
      steps: [
        OmnixWorkflowStep(
          id: 'first',
          tool: 'host_test',
          arguments: {},
          retry: OmnixRetrySafety.requiresReconciliation,
        ),
      ],
    );
    final json = definition.toJson();
    expect(json.containsKey('grants'), isFalse);
    expect((json['steps'] as List).single['retry'], 'RequiresReconciliation');
    expect(() => definition.steps.clear(), throwsUnsupportedError);
  });
  test('progress preserves a present JSON null result', () {
    final progress = OmnixWorkflowProgress.decode(
      jsonEncode({
        'version': 1,
        'id': 'job',
        'cancelled': false,
        'steps': [
          {
            'id': 'first',
            'executor': 'host_test',
            'state': 'Succeeded',
            'output': {'value': null},
          },
        ],
      }),
    );
    expect(progress.completed, isTrue);
    expect(progress.steps.single.hasOutput, isTrue);
    expect(progress.steps.single.output, isNull);
    expect(
      () => OmnixWorkflowProgress.decode('{"version":3}'),
      throwsFormatException,
    );
  });
  test(
    'host exceptions produce uncertainty for durable execution only',
    () async {
      final extensions = OmnixAgentExtensions(
        tools: [
          OmnixHostTool(
            name: 'host_test',
            description: 'Test',
            parameters: {},
            execute: (_) async => throw StateError('After effect'),
          ),
        ],
        grants: ['host_test'],
      );
      final request = jsonEncode({
        'requestId': '1',
        'callId': 'stable',
        'toolName': 'host_test',
        'arguments': {},
      });
      expect(
        (jsonDecode(await extensions.executeWorkflowRequest(request))
            as Map)['result']['status'],
        'interrupted',
      );
      expect(
        (jsonDecode(await extensions.executeRequest(request))
            as Map)['result']['status'],
        'failed',
      );
      expect(
        OmnixToolRequest.fromJson(
          jsonDecode(request) as Map<String, dynamic>,
        ).callId,
        'stable',
      );
    },
  );
}
