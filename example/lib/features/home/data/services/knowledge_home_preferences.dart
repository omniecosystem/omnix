import 'dart:convert';
import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;

// Host preference only: no native handles, checkpoints or execution authority.
final class KnowledgeHomePreferences {
  KnowledgeHomePreferences(this.file);
  final File file;

  Future<OmnixLocalKnowledge?> load() async {
    if (!await file.exists()) return null;
    final config = decode(jsonDecode(await file.readAsString()));
    if (!await File(config.embeddingModel).exists() ||
        !await File(
          p.join(config.storePath, 'omnix-vector-profile.json'),
        ).exists()) {
      throw StateError(
        'Saved Knowledge model or index is missing. Reattach Knowledge.',
      );
    }
    return config;
  }

  Future<void> save(OmnixLocalKnowledge config) async {
    final value = {
      'version': 1,
      'embeddingModel': config.embeddingModel,
      'storePath': config.storePath,
      'topK': config.topK,
      'threshold': config.threshold,
      'publicOnly': config.publicOnly,
    };
    decode(
      value,
    ); // Reject invalid settings before replacing the last good file.
    final pending = File(
      p.join(p.dirname(file.path), '${p.basename(file.path)}.pending'),
    );
    try {
      await pending.writeAsString(jsonEncode(value), flush: true);
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  static OmnixLocalKnowledge decode(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['embeddingModel'] is! String ||
        value['storePath'] is! String ||
        value['topK'] is! int ||
        value['threshold'] is! num ||
        value['publicOnly'] is! bool) {
      throw const FormatException('Invalid saved Knowledge settings.');
    }
    final model = value['embeddingModel'] as String;
    final store = value['storePath'] as String;
    final topK = value['topK'] as int;
    final threshold = (value['threshold'] as num).toDouble();
    if (!p.isAbsolute(model) ||
        !p.isAbsolute(store) ||
        topK < 1 ||
        topK > 16 ||
        !threshold.isFinite ||
        threshold < -1 ||
        threshold > 1) {
      throw const FormatException('Invalid saved Knowledge paths or limits.');
    }
    return OmnixLocalKnowledge(
      embeddingModel: model,
      storePath: store,
      topK: topK,
      threshold: threshold,
      publicOnly: value['publicOnly'] as bool,
      // Restart may reopen an existing index, never silently create a new one.
      createStore: false,
    );
  }
}
