// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  test('native round budget is explicit and bounded', () {
    for (final rounds in [1, 4, 10, 32]) {
      final extensions = OmnixAgentExtensions(grants: [], maxRounds: rounds);
      expect(jsonDecode(extensions.encodeRegistration())['maxRounds'], rounds);
    }
    expect(OmnixAgentExtensions(grants: []).maxRounds, 4);
    for (final rounds in [0, -1, 33]) {
      expect(
        () => OmnixAgentExtensions(grants: [], maxRounds: rounds),
        throwsArgumentError,
      );
    }
  });
  test('delegated scope requires a bounded session budget', () {
    expect(
      () => OmnixApprovalPolicy(mode: OmnixAutonomyMode.delegatedScope),
      throwsArgumentError,
    );
    final policy = OmnixApprovalPolicy(
      mode: OmnixAutonomyMode.delegatedScope,
      automaticTools: ['clock'],
      maxAutomaticCalls: 2,
      validForSeconds: 60,
    );
    expect(policy.toJson()['maxAutomaticCalls'], 2);
    expect(() => policy.automaticTools.add('other'), throwsUnsupportedError);
  });
  test(
    'approval callback never dispatches an executor or grants access',
    () async {
      var executions = 0;
      var reviews = 0;
      final extensions = OmnixAgentExtensions(
        tools: [
          OmnixHostTool(
            name: 'clock',
            description: 'Clock',
            parameters: {},
            execute: (_) async {
              executions++;
              return {};
            },
          ),
        ],
        grants: ['clock'],
        approvalPolicy: OmnixApprovalPolicy(
          mode: OmnixAutonomyMode.reviewEveryCall,
        ),
        approve: (_) async {
          reviews++;
          return false;
        },
      );
      final reply =
          jsonDecode(
                await extensions.executeRequest(
                  jsonEncode({
                    'phase': 'approval',
                    'requestId': 'review-1',
                    'toolName': 'clock',
                    'arguments': {},
                  }),
                ),
              )
              as Map;
      expect(reply['requestId'], 'review-1');
      expect(reply['result'], {'approved': false});
      expect(executions, 0);
      expect(reviews, 1);
      final unknown =
          jsonDecode(
                await extensions.executeRequest(
                  jsonEncode({
                    'phase': 'approval',
                    'requestId': 'review-2',
                    'toolName': 'unknown',
                    'arguments': {},
                  }),
                ),
              )
              as Map;
      expect(unknown['result'], {'approved': false});
      expect(reviews, 1);
      expect(
        jsonDecode(extensions.encodeRegistration())['approvalPolicy']['mode'],
        'reviewEveryCall',
      );
    },
  );
  test('missing or throwing reviewer fails closed', () async {
    for (final OmnixToolApprovalHandler? approve in [
      null,
      (_) async => throw StateError('private'),
    ]) {
      final extensions = OmnixAgentExtensions(
        grants: ['clock'],
        approvalPolicy: OmnixApprovalPolicy(
          mode: OmnixAutonomyMode.scopedAssistance,
        ),
        approve: approve,
      );
      final reply = await extensions.executeRequest(
        jsonEncode({
          'phase': 'approval',
          'requestId': '1',
          'toolName': 'clock',
          'arguments': {},
        }),
      );
      expect(jsonDecode(reply)['result']['approved'], false);
      expect(reply, isNot(contains('private')));
    }
  });
  OmnixHostTool clock({bool fails = false}) => OmnixHostTool(
    name: 'clock',
    description: 'Read clock',
    parameters: {
      'type': 'object',
      'properties': <String, Object?>{},
      'required': <String>[],
      'additionalProperties': false,
    },
    execute: (request) async {
      expect(request.arguments, isEmpty);
      if (fails) throw StateError('private implementation details');
      return {'utc': '2031-05-06'};
    },
  );
  test(
    'registrations and skills serialize separately from execution grants',
    () {
      final skill = OmnixSkill(
        name: 'clock-skill',
        description: 'Time',
        instructions: 'Use clock',
        requiredTools: ['clock'],
      );
      expect(OmnixSkill.fromJson(skill.toJson()).requiredTools, ['clock']);
      final extensions = OmnixAgentExtensions(
        tools: [clock()],
        skills: [skill],
        grants: [],
        selectedSkills: [],
      );
      final encoded =
          jsonDecode(extensions.encodeRegistration()) as Map<String, dynamic>;
      expect(encoded['grants'], isEmpty);
      expect(encoded['selectedSkills'], isEmpty);
      expect((encoded['tools'] as List).single['name'], 'clock');
      expect(() => extensions.grants.add('clock'), throwsUnsupportedError);
      expect(
        () =>
            OmnixAgentExtensions(tools: [clock(), clock()], grants: ['clock']),
        throwsArgumentError,
      );
    },
  );
  test(
    'host replies preserve correlation and refuse unknown or ungranted calls',
    () async {
      final extensions = OmnixAgentExtensions(
        tools: [clock()],
        grants: ['clock'],
      );
      final reply =
          jsonDecode(
                await extensions.executeRequest(
                  jsonEncode({
                    'requestId': 'a:1',
                    'toolName': 'clock',
                    'arguments': <String, dynamic>{},
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(reply['requestId'], 'a:1');
      expect(reply['result'], {'utc': '2031-05-06'});
      for (final name in ['unknown', 'clock']) {
        final denied = OmnixAgentExtensions(tools: [clock()], grants: []);
        await expectLater(
          denied.executeRequest(
            jsonEncode({
              'requestId': 'a:2',
              'toolName': name,
              'arguments': <String, dynamic>{},
            }),
          ),
          throwsStateError,
        );
      }
    },
  );
  test('host exceptions become sanitized tool failures', () async {
    final extensions = OmnixAgentExtensions(
      tools: [clock(fails: true)],
      grants: ['clock'],
    );
    final reply = await extensions.executeRequest(
      jsonEncode({
        'requestId': 'a:1',
        'toolName': 'clock',
        'arguments': <String, dynamic>{},
      }),
    );
    expect(reply, contains('failed'));
    expect(reply, isNot(contains('private')));
  });

  test(
    'granted tools need no extra review without an approval policy',
    () async {
      final extensions = OmnixAgentExtensions(
        tools: [clock()],
        grants: ['clock'],
        approve: (_) async => throw StateError('Review must not be requested.'),
      );
      final reply =
          jsonDecode(
                await extensions.executeRequest(
                  jsonEncode({
                    'requestId': 'unreviewed-1',
                    'toolName': 'clock',
                    'arguments': <String, dynamic>{},
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(reply['result'], {'utc': '2031-05-06'});
      expect(
        jsonDecode(extensions.encodeRegistration()),
        isNot(contains('approvalPolicy')),
      );
    },
  );

  test(
    'workflow handler exceptions report uncertainty without private details',
    () async {
      final extensions = OmnixAgentExtensions(
        tools: [clock(fails: true)],
        grants: ['clock'],
      );
      final raw = await extensions.executeWorkflowRequest(
        jsonEncode({
          'requestId': 'workflow-1',
          'callId': 'durable-step-1',
          'toolName': 'clock',
          'arguments': <String, dynamic>{},
        }),
      );
      final reply = jsonDecode(raw) as Map<String, dynamic>;
      expect(reply['requestId'], 'workflow-1');
      expect(reply['result'], {
        'status': 'interrupted',
        'error': 'Host tool failed.',
      });
      expect(raw, isNot(contains('private')));
    },
  );

  test(
    'explicit host failures remain evidence for both dispatch modes',
    () async {
      const result = {'status': 'failed', 'reason': 'Target unavailable.'};
      final extensions = OmnixAgentExtensions(
        tools: [
          OmnixHostTool(
            name: 'test-action',
            description: 'Returns a synthetic failure.',
            parameters: {},
            execute: (_) async => result,
          ),
        ],
        grants: ['test-action'],
      );
      final request = jsonEncode({
        'requestId': 'failure-1',
        'toolName': 'test-action',
        'arguments': <String, dynamic>{},
      });
      for (final dispatch in [
        extensions.executeRequest,
        extensions.executeWorkflowRequest,
      ]) {
        final reply =
            jsonDecode(await dispatch(request)) as Map<String, dynamic>;
        expect(reply['requestId'], 'failure-1');
        expect(reply['result'], result);
      }
    },
  );
}
