import 'dart:io';
import 'package:omnix/omnix_session.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_LEAN_TEST_BRIDGE'];
  test(
    'lean native root reports missing Knowledge instead of using a Dart fallback',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      // The root package's test configuration selects no native modules. This
      // exercises the real generated bridge without models, stores, or downloads.
      await expectLater(
        OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          knowledge: const OmnixLocalKnowledge(
            embeddingModel: 'unused-model',
            storePath: 'unused-index',
          ),
        ),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('Local Knowledge is not compiled'),
          ),
        ),
      );
    },
    skip: bridge == null,
  );
}
