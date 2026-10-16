import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import '../../../../../../test/src/knowledge_indexing_test.dart'
    show IndexTransport;

void main() {
  test('panel never closes a borrowed Home engine', () async {
    final transport = IndexTransport();
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    final panel = NativeKnowledgeDemoBackend(
      '/index',
      sharedEngine: (_) async => engine,
      rootIndexing: true,
      openEngine: (_) async =>
          throw StateError('Borrowed engine must be reused'),
    );
    await panel.indexAndReopen(
      encoder: '/model',
      tokenizer: '',
      legacyGecko: false,
      title: 'Title',
      content: 'Content',
    );
    expect(transport.records, hasLength(1));
    await panel.indexAndReopen(
      encoder: '/model',
      tokenizer: '',
      legacyGecko: false,
      title: 'Second document',
      content: 'a' * 1024,
    );
    expect(transport.records, hasLength(2));
    expect(
      jsonDecode(transport.records[0])['id'],
      isNot(jsonDecode(transport.records[1])['id']),
    );
    expect((await panel.retrieve('query')).single.content, 'query');
    await panel.releaseForHome();
    await panel.close();
    expect(transport.engineCloses, 0);
    await engine.close();
    expect(transport.engineCloses, 1);
  });
  test(
    'owned panel reopens durable root store and releases its own engines',
    () async {
      final transports = <IndexTransport>[];
      final creation = <bool>[];
      final panel = NativeKnowledgeDemoBackend(
        '/index',
        rootIndexing: true,
        openEngine: (config) async {
          expect(config.storePath, p.join('/index', 'embeddinggemma2-v1'));
          creation.add(config.createStore);
          final transport = IndexTransport();
          transports.add(transport);
          return OmnixCognitiveEngine.open(
            runtimes: ['litertlm'],
            transport: transport,
            knowledge: config,
          );
        },
      );
      await panel.indexAndReopen(
        encoder: '/model',
        tokenizer: '',
        legacyGecko: false,
        title: 'Title',
        content: 'Content',
      );
      expect(creation, [true, false]);
      expect(transports.first.engineCloses, 1);
      await panel.close();
      expect(transports.last.engineCloses, 1);
    },
  );
}
