import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

abstract interface class VoiceCapture {
  Future<void> start();
  Future<ChatAttachment> stop();
  Future<void> cancel();
  Future<void> close();
}
