import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:omnix_example/features/home/data/services/voice_capture_native.dart';

void main() {
  test(
    'recorded PCM is wrapped as 16 kHz mono PCM16 WAV without conversion',
    () {
      final pcm = Uint8List.fromList([0, 0, 255, 127]);
      final wav = voicePcmToWav(pcm);
      final header = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(header.getUint32(4, Endian.little), wav.length - 8);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), pcm.length);
      expect(wav.sublist(44), pcm);
    },
  );
  test('empty, incomplete and overlong recordings are rejected', () {
    for (final pcm in [Uint8List(0), Uint8List(1), Uint8List(1920002)]) {
      expect(() => voicePcmToWav(pcm), throwsStateError);
    }
  });
}
