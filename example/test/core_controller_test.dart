import 'dart:async';
import 'package:test/test.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'dart:typed_data';
import 'package:omnix_core/omnix_core.dart';

class MediaBackend implements MediaCoreBackend {
  final List<List<ChatAttachment>> turns = [];
  @override
  Stream<String> generateMessage(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) {
    turns.add(attachments);
    return Stream.value('Reply');
  }

  @override
  Stream<String> generate(String model, String prompt) =>
      Stream.value('Text reply');
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

class FakeBackend implements CoreDemoBackend {
  final stream = StreamController<String>();
  int calls = 0;
  bool closed = false;
  @override
  Stream<String> generate(String model, String prompt) {
    calls++;
    return stream.stream;
  }

  @override
  Future<void> stop() => stream.close();
  @override
  Future<void> close() async {
    closed = true;
  }
}

class PreparationBackend extends MediaBackend implements PreparedCoreBackend {
  int generations = 0;
  @override
  Stream<String> generate(String model, String prompt) {
    generations++;
    return super.generate(model, prompt);
  }

  final gate = Completer<void>();
  int preparations = 0;
  bool fail = false;
  @override
  Future<void> prepare(String model) async {
    preparations++;
    await gate.future;
    if (fail) throw StateError('Model unavailable');
  }
}

class MixedBackend extends MediaBackend implements MixedInputCoreBackend {
  @override
  bool get supportsMixedInput => true;
}

void main() {
  test(
    'send displays one message and waits for preparation before inference',
    () async {
      final backend = PreparationBackend();
      final controller = CoreController(backend)..configureModel('model');
      final preparing = controller.prepare();
      expect(controller.canCompose, isTrue);
      final sending = controller.send('model', 'Hello while loading');
      expect(controller.messages.single.text, 'Hello while loading');
      expect(controller.sending, isTrue);
      expect(controller.canCompose, isFalse);
      await controller.send('model', 'Duplicate');
      expect(controller.messages.length, 1);
      expect(backend.generations, 0);
      backend.gate.complete();
      await preparing;
      await sending;
      expect(backend.generations, 1);
      expect(controller.messages.length, 2);
      expect(controller.sending, isFalse);
      await controller.close();
      controller.dispose();
    },
  );

  test(
    'failed preparation retains submitted bubble without running inference',
    () async {
      final backend = PreparationBackend()..fail = true;
      final controller = CoreController(backend)..configureModel('model');
      final preparing = controller.prepare();
      final sending = controller.send('model', 'Keep this request');
      backend.gate.complete();
      await preparing;
      await sending;
      expect(backend.generations, 0);
      expect(controller.error, contains('Model unavailable'));
      expect(controller.messages.single.text, 'Keep this request');
      expect(controller.busy, isFalse);
      await controller.close();
      controller.dispose();
    },
  );

  test(
    'stop cancels a waiting message and close waits for preparation',
    () async {
      final backend = PreparationBackend();
      final controller = CoreController(backend)..configureModel('model');
      final preparing = controller.prepare();
      final sending = controller.send('model', 'Do not run');
      await controller.stop();
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      backend.gate.complete();
      await preparing;
      await sending;
      await closing;
      expect(backend.generations, 0);
      controller.dispose();
    },
  );

  test(
    'mixed-input backend accepts audio after text without marking chat temporary',
    () async {
      final backend = MixedBackend();
      final controller = CoreController(backend);
      await controller.send('model', 'First text');
      expect(controller.canAddAttachments, isTrue);
      await controller.send(
        'model',
        '',
        attachments: [
          ChatAttachment(
            'Voice.wav',
            OmnixInputPart.audio(Uint8List.fromList([1, 2])),
          ),
        ],
      );
      expect(backend.turns.length, 1);
      expect(controller.messages.length, 4);
      expect(controller.temporaryMediaChat, isFalse);
      await controller.close();
      controller.dispose();
    },
  );
  test(
    'preparation reports readiness, guards duplicate loads and permits retry',
    () async {
      final backend = PreparationBackend()..fail = true;
      final controller = CoreController(backend)..configureModel('model');
      final pending = controller.prepare();
      expect(controller.busy, isTrue);
      expect(controller.readiness, ChatReadiness.preparing);
      await controller.prepare();
      expect(backend.preparations, 1);
      backend.gate.complete();
      await pending;
      expect(controller.readiness, ChatReadiness.failed);
      expect(controller.error, contains('Model unavailable'));
      expect(controller.busy, isFalse);
      backend.fail = false;
      await controller.prepare();
      expect(controller.readiness, ChatReadiness.ready);
      expect(controller.error, isNull);
      expect(controller.messages, isEmpty);
      await controller.close();
      controller.dispose();
    },
  );
  final image = ChatAttachment(
    'image.png',
    OmnixInputPart.image(Uint8List.fromList([1])),
  );
  test('media and text followups use media backend until a new chat', () async {
    final backend = MediaBackend();
    final controller = CoreController(backend);
    await controller.send('model', '', attachments: [image]);
    await controller.send('model', 'Recall the image');
    expect(backend.turns.length, 2);
    expect(backend.turns.first.single, same(image));
    expect(backend.turns.last, isEmpty);
    expect(controller.messages.first.attachments.single, same(image));
    expect(controller.temporaryMediaChat, isTrue);
    await controller.select(null);
    expect(controller.temporaryMediaChat, isFalse);
    await controller.send('model', 'text');
    expect(backend.turns.length, 2);
    await controller.close();
    controller.dispose();
  });
  test('media cannot modify an existing text conversation', () async {
    final backend = MediaBackend();
    final controller = CoreController(backend);
    await controller.send('model', 'text');
    final previous = List.of(controller.messages);
    await controller.send('model', '', attachments: [image]);
    expect(backend.turns, isEmpty);
    expect(controller.messages, previous);
    expect(controller.error, contains('new chat'));
    expect(controller.temporaryMediaChat, isFalse);
    await controller.close();
    controller.dispose();
  });
  test(
    'assembles deltas, rejects concurrent sends and drains on close',
    () async {
      final backend = FakeBackend();
      final controller = CoreController(backend);
      final generation = controller.send('trusted', 'question');
      await controller.send('trusted', 'duplicate');
      backend.stream.add('Hello');
      backend.stream.add(' world');
      await controller.close();
      await generation;
      expect(backend.calls, 1);
      expect(controller.answer, 'Hello world');
      expect(controller.busy, isFalse);
      expect(backend.closed, isTrue);
      controller.dispose();
    },
  );
  test('reports backend failure without staying busy', () async {
    final backend = FakeBackend();
    final controller = CoreController(backend);
    final generation = controller.send('trusted', 'question');
    backend.stream.addError(StateError('test failure'));
    await generation;
    expect(controller.error, contains('test failure'));
    expect(controller.busy, isFalse);
    await controller.close();
    controller.dispose();
  });
}
