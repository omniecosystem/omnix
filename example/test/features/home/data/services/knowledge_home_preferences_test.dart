import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/knowledge_home_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late KnowledgeHomePreferences preferences;
  late OmnixLocalKnowledge config;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('knowledge-preferences-');
    preferences = KnowledgeHomePreferences(
      File(p.join(directory.path, 'home.json')),
    );
    final model = File(p.join(directory.path, 'embedding.litertlm'));
    await model.writeAsString('test model');
    final index = Directory(p.join(directory.path, 'index'));
    await index.create();
    await File(
      p.join(index.path, 'omnix-vector-profile.json'),
    ).writeAsString('{}');
    config = OmnixLocalKnowledge(
      embeddingModel: model.path,
      storePath: index.path,
      topK: 4,
      threshold: 0.25,
      publicOnly: true,
      createStore: true,
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('absent preference leaves Knowledge unconfigured', () async {
    expect(await preferences.load(), isNull);
  });
  test('reopens paths and scope without creation authority', () async {
    await preferences.save(config);
    final reopened = await KnowledgeHomePreferences(preferences.file).load();
    expect(reopened!.embeddingModel, config.embeddingModel);
    expect(reopened.storePath, config.storePath);
    expect(reopened.topK, 4);
    expect(reopened.threshold, 0.25);
    expect(reopened.publicOnly, isTrue);
    expect(reopened.createStore, isFalse);
    // Replacement is supported on Windows as well as Android.
    await preferences.save(
      OmnixLocalKnowledge(
        embeddingModel: config.embeddingModel,
        storePath: config.storePath,
        topK: 2,
      ),
    );
    expect((await preferences.load())!.topK, 2);
  });
  test('invalid save preserves last good configuration', () async {
    await preferences.save(config);
    await expectLater(
      preferences.save(
        OmnixLocalKnowledge(
          embeddingModel: 'relative',
          storePath: config.storePath,
        ),
      ),
      throwsFormatException,
    );
    expect((await preferences.load())!.embeddingModel, config.embeddingModel);
  });
  test('missing model or index is explicit and never recreated', () async {
    await preferences.save(config);
    await File(config.embeddingModel).delete();
    await expectLater(preferences.load(), throwsStateError);
    await File(config.embeddingModel).writeAsString('test model');
    await Directory(config.storePath).delete(recursive: true);
    await expectLater(preferences.load(), throwsStateError);
    expect(await Directory(config.storePath).exists(), isFalse);
  });
  test('malformed settings fail instead of granting implicit access', () async {
    await preferences.file.writeAsString('{broken');
    await expectLater(preferences.load(), throwsFormatException);
    for (final edit in <void Function(Map<String, dynamic>)>[
      (v) => v['version'] = 2,
      (v) => v.remove('publicOnly'),
      (v) => v['publicOnly'] = 'true',
      (v) => v['topK'] = 17,
      (v) => v['threshold'] = double.nan,
      (v) => v['storePath'] = 'relative',
    ]) {
      final value = <String, dynamic>{
        'version': 1,
        'embeddingModel': config.embeddingModel,
        'storePath': config.storePath,
        'publicOnly': true,
        'topK': 3,
        'threshold': 0.7,
      };
      edit(value);
      expect(
        () => KnowledgeHomePreferences.decode(value),
        throwsFormatException,
      );
    }
  });
}
