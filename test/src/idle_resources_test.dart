import 'dart:async';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import 'knowledge_indexing_test.dart' as fixtures;

class ResourceTransport extends fixtures.IndexTransport
    implements OmnixResourceTransport {
  Completer<String>? release;
  int requests = 0;
  @override
  Future<String> releaseIdleResources(BigInt engine) {
    requests++;
    return release?.future ??
        Future.value('{"knowledge":"Busy","retainedChatModels":1}');
  }
}

void main() {
  test(
    'pressure request does not wait for indexing, close waits for both',
    () async {
      final transport = ResourceTransport()
        ..pending = Completer<void>()
        ..release = Completer<String>();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final indexing = engine.indexDocument(
        const OmnixKnowledgeDocument(
          id: 'id',
          documentId: 'doc',
          title: 'Title',
          content: 'Text',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final release = engine.releaseIdleResources();
      expect(transport.requests, 1);
      final closing = engine.close();
      transport.pending!.complete();
      await indexing;
      await Future<void>.delayed(Duration.zero);
      expect(transport.engineCloses, 0);
      transport.release!.complete(
        '{"knowledge":"Released","retainedChatModels":1}',
      );
      final report = await release;
      expect(report.knowledge, OmnixIdleRelease.released);
      expect(report.retainedChatModels, 1);
      await closing;
      expect(transport.engineCloses, 1);
      await expectLater(engine.releaseIdleResources(), throwsStateError);
    },
  );
  test(
    'busy release is not retried and legacy transports reject explicitly',
    () async {
      final transport = ResourceTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      expect(
        (await engine.releaseIdleResources()).knowledge,
        OmnixIdleRelease.busy,
      );
      expect(transport.requests, 1);
      await engine.close();
      final legacy = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: fixtures.IndexTransport(),
      );
      await expectLater(legacy.releaseIdleResources(), throwsUnsupportedError);
      await legacy.close();
    },
  );
  test('unknown or invalid resource observations are never guessed', () {
    for (final raw in [
      '{}',
      '{"knowledge":"Unknown","retainedChatModels":0}',
      '{"knowledge":"Released","retainedChatModels":-1}',
    ]) {
      expect(() => OmnixIdleResourceReport.decode(raw), throwsFormatException);
    }
  });
}
