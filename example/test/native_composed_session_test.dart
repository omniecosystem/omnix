import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:path/path.dart' as p;
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/home/data/repositories/composed_chat_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  final embedding = Platform.environment['OMNIX_SESSION_TEST_EMBEDDING'];
  test(
    'native agent searches the real index and returns separate evidence',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-agent-index-',
      );
      final backend = NativeKnowledgeDemoBackend(
        p.join(directory.path, 'index'),
      );
      OmnixCognitiveEngine? engine;
      OmnixAgentSession? agent;
      ComposedChatRepository? repository;
      try {
        await backend.indexAndReopen(
          encoder: embedding!,
          tokenizer: '',
          legacyGecko: false,
          title: 'Device reset manual',
          content:
              'The device reset code is 73921. Enter this code before pressing reset.',
        );
        final registration = await backend.releaseForHome();
        engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          knowledge: registration,
        );
        agent = await engine.startKnowledgeAgent(
          modelPath: model!,
          instructions:
              'Search local Knowledge for device reset questions. Answer briefly using its evidence.',
        );
        final events = await agent
            .sendEvents('What is the device reset code in my local manual?')
            .toList();
        final reply = events
            .singleWhere((event) => event.kind == OmnixAgentEventKind.completed)
            .reply!;
        expect(
          events
              .where((event) => event.kind == OmnixAgentEventKind.text)
              .length,
          greaterThan(1),
        );
        expect(
          events.where(
            (event) => event.kind == OmnixAgentEventKind.toolStarted,
          ),
          isNotEmpty,
        );
        expect(reply.toolCalls, greaterThan(0));
        expect(reply.text, contains('73921'));
        expect(
          reply.sources.map((s) => s.title),
          contains('Device reset manual'),
        );
        expect(reply.sources.first.content, contains('73921'));
        var requestedCancel = false;
        var sawCancellation = false;
        var sawCompletion = false;
        await for (final event in agent.sendEvents(
          'Count from one to one hundred, spelling out each number.',
        )) {
          if (event.kind == OmnixAgentEventKind.text && !requestedCancel) {
            requestedCancel = true;
            agent.cancelGeneration();
          }
          if (event.kind == OmnixAgentEventKind.cancelled) {
            sawCancellation = true;
          }
          if (event.kind == OmnixAgentEventKind.completed) sawCompletion = true;
        }
        expect(requestedCancel, isTrue);
        expect(sawCancellation, isTrue);
        expect(sawCompletion, isFalse);
        await agent.close();
        agent = null;
        agent = await engine.startKnowledgeAgent(
          modelPath: model,
          allowEmailDrafts: true,
        );
        final emailEvents = await agent
            .sendEvents(
              'Prepare an email draft to alex@example.com with subject Hello and body Can we meet at ten? Do not send anything.',
            )
            .toList();
        final emailReply = emailEvents
            .singleWhere((event) => event.kind == OmnixAgentEventKind.completed)
            .reply!;
        expect(emailReply.toolCalls, greaterThan(0));
        expect(emailReply.intents, isNotEmpty);
        expect(emailReply.intents.first.recipient, 'alex@example.com');
        expect(emailReply.intents.first.subject, 'Hello');
        expect(emailReply.intents.first.body, contains('ten'));
        await agent.close();
        agent = null;
        var clockCalls = 0;
        agent = await engine.startAgent(
          modelPath: model,
          extensions: OmnixAgentExtensions(
            tools: [
              OmnixHostTool(
                name: 'host_time',
                description:
                    'Read the current UTC clock and its verification code.',
                parameters: {
                  'type': 'object',
                  'properties': <String, Object?>{},
                  'required': <String>[],
                  'additionalProperties': false,
                },
                execute: (request) async {
                  clockCalls++;
                  expect(request.arguments, isEmpty);
                  return {
                    'utc': '2031-05-06T10:11:12Z',
                    'clockProof': 'CLOCK73921',
                  };
                },
              ),
            ],
            skills: [
              OmnixSkill(
                name: 'current-time',
                description: 'Read the live clock and verification code.',
                instructions:
                    'Call host_time with no arguments. Return its clockProof exactly.',
                requiredTools: ['host_time'],
              ),
            ],
            grants: ['host_time'],
            selectedSkills: ['current-time'],
          ),
        );
        final clockEvents = await agent
            .sendEvents(
              'Load the current-time skill and use it to tell me the clock verification code.',
            )
            .toList();
        expect(clockCalls, greaterThan(0));
        expect(
          clockEvents
              .where((e) => e.kind == OmnixAgentEventKind.toolFinished)
              .map((e) => e.toolName),
          containsAll(['load_skill', 'host_time']),
        );
        expect(clockEvents.last.reply!.text, contains('CLOCK73921'));
        await agent.close();
        agent = null;
        final entered = Completer<void>();
        final lateResult = Completer<Object?>();
        agent = await engine.startAgent(
          modelPath: model,
          extensions: OmnixAgentExtensions(
            tools: [
              OmnixHostTool(
                name: 'host_time',
                description: 'Read the current UTC time.',
                parameters: {
                  'type': 'object',
                  'properties': <String, Object?>{},
                  'required': <String>[],
                  'additionalProperties': false,
                },
                execute: (_) {
                  entered.complete();
                  return lateResult.future;
                },
              ),
            ],
            grants: ['host_time'],
          ),
        );
        final waiting = agent
            .sendEvents('Use host_time to get the current time.')
            .toList();
        await entered.future.timeout(const Duration(seconds: 30));
        agent.cancelGeneration();
        final stopped = await waiting.timeout(const Duration(seconds: 5));
        lateResult.complete({
          'utc': 'late result must not complete a cancelled turn',
        });
        expect(
          stopped.any((e) => e.kind == OmnixAgentEventKind.cancelled),
          isTrue,
        );
        expect(
          stopped.any((e) => e.kind == OmnixAgentEventKind.completed),
          isFalse,
        );
        await agent.close();
        agent = null;
        await engine.close();
        engine = null;
        repository = ComposedChatRepository(
          OmnixConversationSnapshotStore(
            path: p.join(directory.path, 'chat.sqlite'),
          ),
          knowledge: registration,
        );
        repository.configureInstructions(
          'Search local Knowledge for the device reset code. Answer briefly.',
        );
        repository.configureAgent(true);
        final homeAnswer = await repository
            .generate(
              model,
              'What is the device reset code in my local manual?',
            )
            .join();
        expect(homeAnswer, contains('73921'));
        expect(
          repository.messages.last.sources.map((s) => s.title),
          contains('Device reset manual'),
        );
        expect(repository.currentId, isNull);
        expect(await repository.records(), isEmpty);
      } finally {
        await repository?.close();
        await agent?.close();
        await engine?.close();
        await backend.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || model == null || embedding == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'standalone index hands off to packaged root retrieval and releases its lock',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-root-knowledge-',
      );
      final backend = NativeKnowledgeDemoBackend(
        p.join(directory.path, 'index'),
      );
      ComposedChatRepository? repository;
      try {
        await backend.indexAndReopen(
          encoder: embedding!,
          tokenizer: '',
          legacyGecko: false,
          title: 'Reset manual',
          content:
              'Hold the reset button for ten seconds and wait for the indicator to turn blue before reconnecting.',
        );
        final registration = await backend.releaseForHome();
        repository = ComposedChatRepository(
          OmnixConversationSnapshotStore(
            path: p.join(directory.path, 'chat.sqlite'),
          ),
          knowledge: registration,
        );
        repository.configureInstructions(
          'Answer briefly using the supplied references.',
        );
        final answer = await repository
            .generate(model!, 'How do I reset the device?')
            .join();
        expect(answer, isNotEmpty);
        expect(repository.messages.first.text, 'How do I reset the device?');
        expect(repository.messages.last.sources.single.title, 'Reset manual');
        final saved = repository.currentId!;
        await repository.select(null);
        await repository.select(saved);
        expect(
          repository.messages.last.sources.single.content,
          contains('ten seconds'),
        );
        expect(repository.messages.last.sources.single.score, isNull);
        await repository.close();
        repository = null;
        // A successful reopen demonstrates the root lease was released.
        await backend.indexAndReopen(
          encoder: embedding,
          tokenizer: '',
          legacyGecko: false,
          title: 'Reset manual',
          content: 'Hold reset for ten seconds.',
        );
        expect(answer.toLowerCase(), matches(RegExp(r'\b(ten|10)\b')));
      } finally {
        await repository?.close();
        await backend.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || model == null || embedding == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'packaged root session loads without manual DLL paths',
    () async {
      final engine = await OmnixCognitiveEngine.open(runtimes: ['litertlm']);
      OmnixInteractionSession? session;
      try {
        session = await engine.startSession(
          modelPath: model!,
          instructions: 'Reply briefly.',
          maxOutputTokens: 16,
        );
        expect(await session.send('Say hello.'), isNotEmpty);
        expect(await session.exportHistory(), contains('Say hello.'));
      } finally {
        await session?.close();
        await engine.close();
      }
    },
    skip: !Platform.isWindows || model == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
