import 'dart:io';
import 'dart:typed_data';

import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

import 'native_test_support.dart';

// A generated, self-contained PNG fixture; no download or camera is needed.
Uint8List redImage() {
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> payload) {
    final body = [...type.codeUnits, ...payload];
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    final size = ByteData(4)..setUint32(0, payload.length);
    final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    output.add(size.buffer.asUint8List());
    output.add(body);
    output.add(checksum.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, 64)
    ..setUint32(4, 64)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  chunk('IHDR', header.buffer.asUint8List());
  final pixels = <int>[
    for (var row = 0; row < 64; row++) ...[
      0,
      for (var column = 0; column < 64; column++) ...[255, 0, 0],
    ],
  ];
  chunk('IDAT', ZLibEncoder().convert(pixels));
  chunk('IEND', []);
  return output.takeBytes();
}

void main() {
  final modelPath = Platform.environment['OMNIX_CORE_TEST_MODEL'];
  final audioPath = Platform.environment['OMNIX_CORE_TEST_AUDIO_WAV'];
  test(
    'LiteRT-LM transcribes encoded WAV through the public Dart API',
    () async {
      await initializeTestBridge();
      final model = await OmnixCore().loadModel(
        modelPath: modelPath!,
        enableAudio: true,
      );
      OmnixCoreConversation? chat;
      try {
        chat = await model.startConversation(maxOutputTokens: 64);
        final answer = await chat.sendMessageStream([
          OmnixInputPart.text('Transcribe the spoken words exactly.'),
          OmnixInputPart.audio(await File(audioPath!).readAsBytes()),
        ]).join();
        expect(answer.toLowerCase(), contains('pineapple'));
      } finally {
        await chat?.close();
        await model.close();
      }
    },
    skip: !Platform.isWindows || modelPath == null || audioPath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'LiteRT-LM understands an image through the public Dart API',
    () async {
      await initializeTestBridge();
      final model = await OmnixCore().loadModel(
        modelPath: modelPath!,
        enableImages: true,
      );
      OmnixCoreConversation? chat;
      try {
        chat = await model.startConversation(maxOutputTokens: 64);
        final answer = await chat.sendMessage([
          OmnixInputPart.text(
            'What is the dominant color in this image? Reply with one word.',
          ),
          OmnixInputPart.image(redImage()),
        ]);
        expect(answer.toLowerCase(), contains('red'));
        await expectLater(
          chat.exportHistory(),
          throwsA(
            isA<Object>().having(
              (error) => error.toString(),
              'diagnostic',
              contains('media-history-export-unsupported'),
            ),
          ),
        );
        await chat.sendStream('Count from one to one hundred.').take(1).join();
        final recall = await chat.send(
          'What color was the image? Reply with one word.',
        );
        expect(recall.toLowerCase(), contains('red'));
      } finally {
        await chat?.close();
        await model.close();
      }
    },
    skip: !Platform.isWindows || modelPath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
