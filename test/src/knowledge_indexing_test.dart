import 'dart:async';
import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import '../interaction_session_test.dart' as fixtures;

class IndexTransport extends fixtures.KnowledgeTransport
    implements OmnixKnowledgeIndexTransport {
  final records = <String>[];
  Completer<void>? pending;
  bool busy = false;
  @override
  Future<void> indexKnowledge(BigInt engine, String documentJson) async {
    if (busy) throw StateError('Core(BackendFailure("execution-busy"))');
    records.add(documentJson);
    await pending?.future;
  }

  @override
  Future<List<OmnixInteractionSource>> searchKnowledge(
    BigInt engine,
    String query,
  ) async => [OmnixInteractionSource(title: 'Indexed', content: query)];
}

void main() {
  const document = OmnixKnowledgeDocument(
    id: 'chunk',
    documentId: 'doc',
    title: 'Title',
    content: 'Content',
  );
  const knowledge = OmnixLocalKnowledge(
    embeddingModel: '/model',
    storePath: '/index',
    createStore: true,
  );
  test('explicit creation and document visibility are host supplied', () async {
    final transport = IndexTransport();
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
      knowledge: knowledge,
    );
    await engine.indexDocument(document);
    expect(transport.configuration!.createStore, isTrue);
    expect(jsonDecode(transport.records.single)['public'], isFalse);
    expect((await engine.retrieveSources('query')).single.content, 'query');
    await engine.close();
    await expectLater(engine.indexDocument(document), throwsStateError);
  });
  test(
    'old transports remain compatible but reject indexing and creation',
    () async {
      await expectLater(
        OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: fixtures.KnowledgeTransport(),
          knowledge: knowledge,
        ),
        throwsUnsupportedError,
      );
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: fixtures.Transport(),
      );
      await expectLater(engine.indexDocument(document), throwsUnsupportedError);
      await engine.close();
    },
  );
  test(
    'close waits for admitted indexing and rejection never retries',
    () async {
      final transport = IndexTransport()..busy = true;
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      await expectLater(
        engine.indexDocument(document),
        throwsA(isA<OmnixExecutionException>()),
      );
      expect(transport.records, isEmpty);
      transport
        ..busy = false
        ..pending = Completer<void>();
      final indexing = engine.indexDocument(document);
      await Future<void>.delayed(Duration.zero);
      final closing = engine.close();
      await Future<void>.delayed(Duration.zero);
      expect(transport.engineCloses, 0);
      transport.pending!.complete();
      await indexing;
      await closing;
      expect(transport.engineCloses, 1);
    },
  );
  test('invalid documents are rejected before native mutation', () {
    expect(
      () => const OmnixKnowledgeDocument(
        id: '',
        documentId: 'doc',
        title: 'Title',
        content: 'Content',
      ).encode(),
      throwsArgumentError,
    );
    expect(
      () => OmnixKnowledgeDocument(
        id: 'id',
        documentId: 'doc',
        title: 'Title',
        content: 'é' * 140000,
      ).encode(),
      throwsArgumentError,
    );
  });
}
