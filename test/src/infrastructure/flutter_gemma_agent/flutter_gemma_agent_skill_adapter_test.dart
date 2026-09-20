import 'package:flutter_gemma_agent/flutter_gemma_agent.dart' as agent;
import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma_agent.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterGemmaAgentSkillAdapter', () {
    test('imports provider skills without leaking provider types', () {
      final adapter = FlutterGemmaAgentSkillAdapter(
        [_skill(type: agent.SkillType.js)],
        permissionResolver: (_) {
          return {OmnixCapabilityPermission('sandbox.javascript')};
        },
      );

      final imported = adapter.skills.single;

      expect(imported.metadata.id, 'calculate-hash');
      expect(imported.metadata.kind, OmnixCapabilityKind.skill);
      expect(imported.instructions, contains('hash'));
      expect(imported.toolIds, {agent.AgentToolNames.runSkill});
      expect(
        imported.metadata.requiredPermissions.single.id,
        'sandbox.javascript',
      );
    });

    test('uses one Omnix snapshot as provider selection authority', () async {
      final source = _skill(type: agent.SkillType.intent);
      final adapter = FlutterGemmaAgentSkillAdapter([source]);
      final registry = OmnixCapabilityRegistry();
      adapter.registerWith(registry);

      var provider = adapter.buildProviderRegistry(registry.snapshot);
      expect(provider.all.map((skill) => skill.name), ['calculate-hash']);
      expect(provider.getSelected(), isEmpty);

      registry.setEnabled('calculate-hash', true);
      provider = adapter.buildProviderRegistry(registry.snapshot);

      final selected = provider.getSelected().single;
      expect(selected.name, 'calculate-hash');
      expect(selected.type, agent.SkillType.intent);
      expect(selected.metadata.homepage, source.metadata.homepage);
      expect(selected.scriptName, source.scriptName);
      await registry.close();
    });

    test(
      'preserves Omnix-authored instructions in the provider registry',
      () async {
        final adapter = FlutterGemmaAgentSkillAdapter([_skill()]);
        final registry = OmnixCapabilityRegistry();
        final imported = adapter.skills.single;
        registry.register(
          OmnixSkill(
            metadata: imported.metadata,
            instructions: 'Use the reviewed instructions.',
            toolIds: imported.toolIds,
          ),
        );

        final provider = adapter.buildProviderRegistry(registry.snapshot);

        expect(
          provider.getSelected().single.instructions,
          'Use the reviewed instructions.',
        );
        await registry.close();
      },
    );

    test('rejects duplicate provider skill names', () {
      expect(
        () => FlutterGemmaAgentSkillAdapter([_skill(), _skill()]),
        throwsArgumentError,
      );
    });
  });
}

agent.Skill _skill({agent.SkillType type = agent.SkillType.textOnly}) =>
    agent.Skill(
      name: 'calculate-hash',
      description: 'Calculates a hash.',
      instructions: 'Calculate the requested hash.',
      type: type,
      metadata: const agent.SkillMetadata(homepage: 'https://example.com'),
      scriptName: 'hash.html',
    );
