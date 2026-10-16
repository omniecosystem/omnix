import 'dart:typed_data';
import 'package:omnix/omnix_session.dart';
import 'package:test/test.dart';
import 'interaction_session_test.dart' show Transport;

class MediaTransport extends Transport implements OmnixMediaSessionTransport {
  bool images = false;
  bool audio = false;
  List<OmnixInteractionInput>? received;
  @override
  Future<BigInt> openMedia(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
  ) async {
    this.images = images;
    this.audio = audio;
    return BigInt.two;
  }

  @override
  Stream<String> messageStream(
    BigInt id,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  ) async* {
    received = parts;
    if (this.fail) throw StateError('native failure');
    yield 'image answer';
  }
}

void main() {
  test(
    'media capability and ordered owned input reach root transport',
    () async {
      final transport = MediaTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      addTearDown(engine.close);
      final session = await engine.startSession(
        modelPath: 'model',
        enableImages: true,
      );
      final bytes = Uint8List.fromList([1, 2]);
      final image = OmnixInteractionInput.image(bytes);
      bytes[0] = 9;
      expect(
        await session.sendMessageStream([
          OmnixInteractionInput.text('Describe'),
          image,
        ]).join(),
        'image answer',
      );
      expect(transport.images, true);
      expect(transport.audio, false);
      expect(transport.received![1].bytes, [1, 2]);
      transport.fail = true;
      await expectLater(
        session.sendMessageStream([image]).drain<void>(),
        throwsStateError,
      );
      expect(transport.sessionCloses, 1);
    },
  );
  test(
    'text-only transport never silently drops requested media capability',
    () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: Transport(),
      );
      addTearDown(engine.close);
      await expectLater(
        engine.startSession(modelPath: 'model', enableAudio: true),
        throwsUnsupportedError,
      );
    },
  );
}
