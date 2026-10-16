import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

const maxKnowledgeTextBytes = 32 * 1024;

final class ImportedKnowledgeText {
  const ImportedKnowledgeText(this.name, this.text);
  final String name;
  final String text;
}

ImportedKnowledgeText decodeKnowledgeText(String name, List<int> bytes) {
  if (![
    '.txt',
    '.md',
    '.csv',
    '.json',
  ].contains(p.extension(name).toLowerCase())) {
    throw UnsupportedError(
      'Import supports UTF-8 TXT, MD, CSV and JSON for now.',
    );
  }
  if (bytes.length > maxKnowledgeTextBytes) {
    throw StateError('Text imports currently support up to 32 KiB.');
  }
  var text = utf8.decode(bytes);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  if (text.trim().isEmpty || text.contains('\u0000')) {
    throw const FormatException(
      'The document is empty or contains binary data.',
    );
  }
  return ImportedKnowledgeText(name, text);
}

Future<ImportedKnowledgeText?> pickKnowledgeText() async {
  final selection = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['txt', 'md', 'csv', 'json'],
    withReadStream: true,
  );
  if (selection == null) return null;
  final file = selection.files.single;
  if (file.size > maxKnowledgeTextBytes) {
    throw StateError('Text imports currently support up to 32 KiB.');
  }
  final stream = file.readStream;
  if (stream == null) {
    throw StateError('The selected document could not be read.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > maxKnowledgeTextBytes) {
      throw StateError('Text imports currently support up to 32 KiB.');
    }
    bytes.add(chunk);
  }
  return decodeKnowledgeText(file.name, bytes.takeBytes());
}
