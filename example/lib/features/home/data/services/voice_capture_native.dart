import 'dart:async';
import 'dart:typed_data';
import 'package:omnix_core/omnix_core.dart';
import 'package:record/record.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/domain/voice_capture.dart';

Uint8List voicePcmToWav(Uint8List pcm) {
  if (pcm.isEmpty || pcm.length.isOdd || pcm.length > 16000 * 2 * 60) {
    throw StateError('Record up to 60 seconds of mono PCM16 audio.');
  }
  final wav = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(wav);
  void tag(int offset, String text) =>
      wav.setRange(offset, offset + 4, text.codeUnits);
  tag(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}

class NativeVoiceCapture implements VoiceCapture {
  final _recorder = AudioRecorder();
  BytesBuilder? _pcm;
  StreamSubscription<Uint8List>? _subscription;
  Object? _failure;
  bool _closed = false;
  Future<void> _tail = Future.value();
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> start() => _enqueue(() async {
    if (_closed) throw StateError('Recorder is closed.');
    if (_pcm != null) throw StateError('Recording is already active.');
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone permission is required to record a message.',
      );
    }
    if (_closed) throw StateError('Recorder is closed.');
    _failure = null;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _pcm = BytesBuilder(copy: false);
    _subscription = stream.listen(
      (chunk) {
        final buffer = _pcm;
        if (buffer == null || _failure != null) return;
        if (buffer.length + chunk.length > 16000 * 2 * 60) {
          _failure = StateError(
            'Recording exceeded 60 seconds. Please try a shorter message.',
          );
          unawaited(_recorder.stop().catchError((Object _) => null));
          return;
        }
        buffer.add(Uint8List.fromList(chunk));
      },
      onError: (Object error) {
        _failure = error;
      },
    );
  });
  @override
  Future<ChatAttachment> stop() => _enqueue(() async {
    try {
      await _recorder.stop();
      await _subscription?.cancel();
      if (_failure != null) throw StateError('Recording failed: $_failure');
      final pcm = _pcm?.takeBytes() ?? Uint8List(0);
      return ChatAttachment(
        'Voice message.wav',
        OmnixInputPart.audio(voicePcmToWav(pcm)),
      );
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _pcm = null;
    }
  });
  @override
  Future<void> cancel() => _enqueue(() async {
    if (_closed && _pcm == null) return;
    try {
      await _recorder.cancel();
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _pcm = null;
      _failure = null;
    }
  });
  @override
  Future<void> close() {
    _closed = true;
    return _enqueue(() async {
      try {
        await _recorder.cancel();
      } finally {
        await _subscription?.cancel();
        _subscription = null;
        _pcm = null;
        await _recorder.dispose();
      }
    });
  }
}
