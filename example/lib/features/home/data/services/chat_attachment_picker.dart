import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:path/path.dart' as p;

import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

Future<ChatAttachment?> pickChatAttachment({bool audioOnly = false}) async {
  final selection = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: audioOnly ? ['wav'] : ['png', 'jpg', 'jpeg', 'wav'],
    withReadStream: true,
  );
  if (selection == null) return null;
  final file = selection.files.single;
  final audio = p.extension(file.name).toLowerCase() == '.wav';
  final limit = audio ? 2 * 1024 * 1024 : 8 * 1024 * 1024;
  if (file.size > limit) {
    throw StateError(
      audio ? 'WAV files must be under 2 MiB.' : 'Images must be under 8 MiB.',
    );
  }
  final stream = file.readStream;
  if (stream == null) throw StateError('The selected file could not be read.');
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > limit) {
      throw StateError('The selected file is too large.');
    }
    bytes.add(chunk);
  }
  final data = bytes.takeBytes();
  return ChatAttachment(
    file.name,
    audio ? OmnixInputPart.audio(data) : OmnixInputPart.image(data),
  );
}
