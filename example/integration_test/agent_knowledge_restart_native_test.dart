import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/knowledge_home_preferences.dart';
import 'package:path/path.dart' as p;

// Run the same installed APK twice, with a process stop between runs.
// Models are reused in place; the fixture never touches Home's saved index.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'grounded agent checkpoint across process restart',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const model = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      const run = String.fromEnvironment('OMNIX_QUALIFICATION_RUN');
      expect(encoder, isNotEmpty);
      expect(model, isNotEmpty);
      expect(RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(run), isTrue);
      await tester.runAsync(() async {
        expect(await File(encoder).exists(), isTrue);
        expect(await File(model).exists(), isTrue);
        final directory = Directory(
          p.join(Directory.systemTemp.path, 'omnix-agent-$run'),
        );
        final checkpointFile = File(p.join(directory.path, 'checkpoint.json'));
        final resume = await checkpointFile.exists();
        final preferences = KnowledgeHomePreferences(
          File(p.join(directory.path, 'knowledge.json')),
        );
        await directory.create(recursive: true);
        var executions = 0;
        var seeded = false;
        OmnixCognitiveEngine? engine;
        OmnixAgentSession? agent;
        OmnixAgentExtensions extensions() => OmnixAgentExtensions(
          tools: [
            OmnixHostTool(
              name: 'qualification_lookup',
              description: 'Returns the public qualification code.',
              parameters: {
                'type': 'object',
                'properties': <String, Object?>{},
                'required': <String>[],
                'additionalProperties': false,
              },
              execute: (_) async {
                executions++;
                return {'status': 'ok', 'code': 'violet-73921'};
              },
            ),
          ],
          grants: ['qualification_lookup', 'search_knowledge'],
          approvalPolicy: OmnixApprovalPolicy(
            mode: OmnixAutonomyMode.scopedAssistance,
            automaticTools: ['qualification_lookup', 'search_knowledge'],
          ),
        );
        const instructions =
            'Use qualification_lookup for the qualification code. '
            'Use search_knowledge for router instructions. Never invent results. '
            'After receiving evidence, answer briefly. For follow-up questions, '
            'reuse results already present unless a fresh lookup is requested.';
        try {
          final config = resume
              ? await preferences.load()
              : OmnixLocalKnowledge(
                  embeddingModel: encoder,
                  storePath: p.join(directory.path, 'index'),
                  createStore: true,
                  threshold: 0,
                );
          expect(config, isNotNull);
          engine = await OmnixCognitiveEngine.open(
            runtimes: ['litertlm'],
            contextTokens: 4096,
            knowledge: config,
          );
          if (!resume) {
            await engine.indexDocument(
              const OmnixKnowledgeDocument(
                id: 'router',
                documentId: 'manual',
                title: 'Router manual',
                content:
                    'Hold the reset button for ten seconds until the light turns blue.',
                public: true,
              ),
            );
            await preferences.save(config!);
          }
          agent = await engine.startAgent(
            modelPath: model,
            instructions: instructions,
            maxOutputTokens: 256,
            extensions: extensions(),
          );
          if (resume) {
            final checkpoint = await checkpointFile.readAsString();
            await agent.restoreCheckpoint(checkpoint);
            expect(
              executions,
              0,
              reason: 'Historical host actions must never run on restore.',
            );
            expect(await agent.exportCheckpoint(), checkpoint);
            final reply = await agent.send(
              'What qualification code did you obtain earlier? '
              'Use the earlier result and reply with that code only. Do not call tools.',
            );
            expect(reply.text, contains('73921'));
            expect(
              (await engine.retrieveSources(
                'How do I reset the router?',
              )).single.title,
              'Router manual',
            );
          } else {
            final reply = await agent.send(
              'Call qualification_lookup, then search_knowledge '
              'for how to reset the router. Give the code and reset instructions.',
            );
            expect(executions, greaterThan(0));
            expect(
              reply.sources.map((source) => source.title),
              contains('Router manual'),
            );
            final checkpoint = await agent.exportCheckpoint();
            expect(checkpoint, contains('violet-73921'));
            await checkpointFile.writeAsString(checkpoint, flush: true);
            seeded = true;
          }
          // Visible phase evidence for the host driver, not a skipped second phase.
          binding.reportData = {'phase': resume ? 'resumed' : 'seeded'};
        } finally {
          await agent?.close();
          await engine?.close();
          // Preserve only a completed seed for the second process; clean after resume.
          if (resume || !seeded) await directory.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
