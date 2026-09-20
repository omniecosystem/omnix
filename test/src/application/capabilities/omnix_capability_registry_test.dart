import 'dart:async';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixCapabilityRegistry', () {
    late OmnixCapabilityRegistry registry;

    setUp(() {
      registry = OmnixCapabilityRegistry();
    });

    tearDown(() async {
      await registry.close();
    });

    test('stores enabled skills and tools in insertion order', () {
      final skill = _skill();
      final tool = _tool();

      registry.register(skill);
      registry.register(tool);

      expect(registry.snapshot.revision, 2);
      expect(registry.snapshot.enabledSkills, [skill]);
      expect(registry.snapshot.enabledTools, [tool]);
      expect(registry.find('clock'), same(tool));
    });

    test('emits only effective enabled-state changes', () async {
      final snapshots = <OmnixCapabilityRegistrySnapshot>[];
      final subscription = registry.snapshots.listen(snapshots.add);
      registry.register(_tool(), enabled: false);

      registry.setEnabled('clock', false);
      registry.setEnabled('clock', true);

      expect(snapshots.map((snapshot) => snapshot.revision), [1, 2]);
      expect(snapshots.last.enabledTools.map((tool) => tool.metadata.id), [
        'clock',
      ]);
      await subscription.cancel();
    });

    test('rejects duplicate registrations', () {
      registry.register(_tool());

      expect(() => registry.register(_tool()), throwsStateError);
    });

    test(
      'returns structured failures for unknown and disabled tools',
      () async {
        final unknown = await registry.executeTool(_invocation('missing'));
        registry.register(_tool(), enabled: false);
        final disabled = await registry.executeTool(_invocation('clock'));

        expect(
          unknown,
          isA<OmnixToolFailure>().having(
            (failure) => failure.code,
            'code',
            OmnixToolFailureCode.notFound,
          ),
        );
        expect(
          disabled,
          isA<OmnixToolFailure>().having(
            (failure) => failure.code,
            'code',
            OmnixToolFailureCode.disabled,
          ),
        );
      },
    );

    test(
      'denies restricted tools unless the host policy allows them',
      () async {
        final restricted = _tool(
          permissions: {OmnixCapabilityPermission('device.location')},
        );
        registry.register(restricted);

        final denied = await registry.executeTool(_invocation('clock'));

        expect(
          denied,
          isA<OmnixToolFailure>().having(
            (failure) => failure.code,
            'code',
            OmnixToolFailureCode.permissionDenied,
          ),
        );
      },
    );

    test('executes a permitted tool with immutable arguments', () async {
      final invocationSeen = Completer<OmnixToolInvocation>();
      await registry.close();
      registry = OmnixCapabilityRegistry(
        permissionPolicy: const _AllowAllPolicy(),
      );
      registry.register(
        _tool(
          permissions: {OmnixCapabilityPermission('device.time')},
          execute: (invocation) {
            invocationSeen.complete(invocation);
            return const OmnixToolSuccess('12:00');
          },
        ),
      );

      final result = await registry.executeTool(
        OmnixToolInvocation(
          toolId: 'clock',
          callId: 'call-7',
          arguments: const {'timezone': 'UTC'},
        ),
      );

      expect(result, isA<OmnixToolSuccess>());
      expect((result as OmnixToolSuccess).value, '12:00');
      expect((await invocationSeen.future).callId, 'call-7');
      final invocation = await invocationSeen.future;
      expect(
        () => invocation.arguments['timezone'] = 'GMT',
        throwsUnsupportedError,
      );
    });

    test('converts executor exceptions to structured failures', () async {
      registry.register(
        _tool(execute: (_) => throw const FormatException('invalid timezone')),
      );

      final result = await registry.executeTool(_invocation('clock'));

      expect(
        result,
        isA<OmnixToolFailure>()
            .having(
              (failure) => failure.code,
              'code',
              OmnixToolFailureCode.executionFailed,
            )
            .having(
              (failure) => failure.message,
              'message',
              contains('invalid timezone'),
            ),
      );
    });

    test('unregisters capabilities and closes deterministically', () async {
      final tool = _tool();
      registry.register(tool);

      expect(registry.unregister('clock'), same(tool));
      expect(registry.unregister('clock'), isNull);

      await registry.close();
      expect(() => registry.register(tool), throwsStateError);
      await expectLater(
        registry.executeTool(_invocation('clock')),
        throwsStateError,
      );
    });
  });

  group('capability validation', () {
    test('rejects empty identity fields', () {
      expect(
        () => OmnixCapabilityMetadata(
          id: ' ',
          kind: OmnixCapabilityKind.skill,
          name: 'Skill',
          description: 'Description',
        ),
        throwsArgumentError,
      );
    });

    test('rejects metadata for the wrong capability kind', () {
      expect(
        () => OmnixSkill(
          metadata: _metadata(kind: OmnixCapabilityKind.tool),
          instructions: 'Read the clock.',
        ),
        throwsArgumentError,
      );
    });
  });
}

OmnixCapabilityMetadata _metadata({
  OmnixCapabilityKind kind = OmnixCapabilityKind.tool,
  Set<OmnixCapabilityPermission> permissions = const {},
}) => OmnixCapabilityMetadata(
  id: kind == OmnixCapabilityKind.tool ? 'clock' : 'time-skill',
  kind: kind,
  name: kind == OmnixCapabilityKind.tool ? 'Clock' : 'Time skill',
  description: 'Provides local time.',
  requiredPermissions: permissions,
);

OmnixSkill _skill() => OmnixSkill(
  metadata: _metadata(kind: OmnixCapabilityKind.skill),
  instructions: 'Use the clock tool when current time is required.',
  toolIds: const {'clock'},
);

OmnixTool _tool({
  Set<OmnixCapabilityPermission> permissions = const {},
  OmnixToolExecutor? execute,
}) => OmnixTool(
  metadata: _metadata(permissions: permissions),
  inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
  execute: execute ?? (_) => const OmnixToolSuccess('12:00'),
);

OmnixToolInvocation _invocation(String toolId) =>
    OmnixToolInvocation(toolId: toolId, callId: 'call-1');

final class _AllowAllPolicy implements OmnixCapabilityPermissionPolicy {
  const _AllowAllPolicy();

  @override
  Future<bool> allows(OmnixCapabilityMetadata capability) async => true;
}
