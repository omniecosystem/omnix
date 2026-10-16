import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:omnix/omnix.dart' show OmnixLocalKnowledge;
import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:omnix_example/features/home/data/services/chat_history_migration.dart';
import 'package:omnix_example/features/home/data/services/knowledge_home_preferences.dart';
import 'package:omnix_example/features/home/data/repositories/composed_chat_repository.dart';
import 'package:omnix_example/features/home/data/services/chat_attachment_picker.dart';
import 'package:omnix_example/features/home/data/services/voice_capture_native.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/presentation/widgets/home_chat_panel.dart';
import 'package:omnix_example/features/home/presentation/widgets/chat_history_panel.dart';
import 'package:omnix_example/features/core/presentation/pages/core_screen.dart';
import 'package:omnix_example/features/knowledge/presentation/pages/knowledge_example_screen.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:omnix_example/features/nexus/presentation/pages/nexus_example_screen.dart';
import 'package:omnix_example/features/nexus/presentation/pages/matter_host_screen.dart';
import 'package:omnix_example/features/storage/presentation/pages/storage_screen.dart';
import 'package:omnix_example/app/showcase_shell.dart';
import 'package:omnix_example/features/workflow/presentation/pages/workflow_screen.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/data/services/model_library_native.dart';
import 'package:omnix_example/features/core/presentation/pages/structured_draft_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CoreController? _controller;
  ModelLibraryController? _models;
  KnowledgeDemoController? _knowledge;
  KnowledgeHomePreferences? _knowledgePreferences;
  Future<void> _releaseHomeKnowledge() async {
    final controller = _controller!;
    if (controller.busy) throw StateError('Wait for Home to finish its turn.');
    await controller.select(null);
    if (controller.error != null) throw StateError(controller.error!);
    (controller.backend as ComposedChatRepository).configureKnowledge(null);
  }

  Future<void> _useKnowledgeInHome() async {
    await _releaseHomeKnowledge();
    final config = await (_knowledge!.backend as NativeKnowledgeDemoBackend)
        .releaseForHome();
    await _knowledgePreferences!.save(config);
    (_controller!.backend as ComposedChatRepository).configureKnowledge(config);
  }

  final _voice = NativeVoiceCapture();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_models?.background());
    if (state == AppLifecycleState.resumed) unawaited(_models?.initialize());
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(_releasePanelIdleResources());
    final backend = _controller?.backend as ComposedChatRepository?;
    if (backend != null) {
      unawaited(
        backend.releaseIdleResources().catchError((Object error) {
          debugPrint('[Omnix][resources] idle release failed: $error');
        }),
      );
    }
  }

  Future<void> _releasePanelIdleResources() async {
    final knowledge = _knowledge?.backend as NativeKnowledgeDemoBackend?;
    try {
      final report = await knowledge?.releaseIdleResources();
      if (report != null) {
        debugPrint(
          '[Omnix][resources] panel knowledge=${report.knowledge.name}',
        );
      }
    } catch (error) {
      debugPrint('[Omnix][resources] panel idle release failed: $error');
    }
  }

  late final Future<void> _ready = _initialize();
  Future<void> _initialize() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final knowledge = KnowledgeDemoController(
      NativeKnowledgeDemoBackend(
        p.join(directory.path, 'knowledge-rag-example-v1'),
        sharedEngine: (config) async {
          final backend = _controller?.backend as ComposedChatRepository?;
          final engine = backend?.knowledgeEngineFor(config);
          if (engine != null) return engine;
          // Release an idle configured index before the panel reopens it.
          // Once Home owns this same index, indexing uses its engine directly.
          if (_controller != null &&
              (_knowledge?.backend as NativeKnowledgeDemoBackend?)
                      ?.rootIndexing ==
                  true) {
            await _releaseHomeKnowledge();
          }
          return null;
        },
      ),
    );
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw UnsupportedError(
        'Composed Home supports Windows and Android only.',
      );
    }
    final store = OmnixConversationSnapshotStore(
      path: p.join(directory.path, 'composed-chat-history.sqlite'),
    );
    final legacyPath = p.join(directory.path, 'native-chat-history.sqlite');
    if (await File(legacyPath).exists()) {
      final legacy = OmnixConversationSnapshotStore(path: legacyPath);
      try {
        await importLegacyHomeHistory(legacy, store);
      } finally {
        await legacy.close();
      }
    }
    // Example host preference, not an engine policy or a paid entitlement.
    final toolsPreference = File(p.join(directory.path, 'home-tools-enabled'));
    final toolsEnabled =
        !await toolsPreference.exists() ||
        (await toolsPreference.readAsString()).trim() == 'true';
    final preferences = KnowledgeHomePreferences(
      File(p.join(directory.path, 'home-knowledge.json')),
    );
    _knowledgePreferences = preferences;
    // Missing/corrupt preferences must not prevent using Home without Knowledge.
    // Native reopening still verifies the encoder/index profile independently.
    OmnixLocalKnowledge? restoredKnowledge;
    if ((knowledge.backend as NativeKnowledgeDemoBackend).rootIndexing) {
      try {
        restoredKnowledge = await preferences.load();
      } catch (error) {
        knowledge.error = 'Knowledge was not restored: $error';
        debugPrint('[Omnix][knowledge] ${knowledge.error}');
      }
    }
    final controller = CoreController(
      ComposedChatRepository(
        store,
        knowledge: restoredKnowledge,
        sharedToolAvailability: true,
        initialToolsEnabled: toolsEnabled,
        saveToolAvailability: (enabled) async {
          await toolsPreference.writeAsString('$enabled', flush: true);
        },
      ),
    );
    if (!mounted) {
      await controller.close();
      controller.dispose();
      knowledge.dispose();
      await knowledge.close();
      return;
    }
    _controller = controller;
    _knowledge = knowledge;
    await controller.initialize();
    if (!mounted) return;
    final models = ModelLibraryController(
      NativeModelLibraryBackend(p.join(directory.path, 'models-v1')),
    );
    _models = models;
    await models.initialize();
    final installedChat = models.models.where(
      (model) => model.spec.role == 'chat',
    );
    if (installedChat.isNotEmpty) {
      controller.configureModel(installedChat.first.path);
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (Platform.isWindows && local != null) {
      final candidate = p.join(
        local,
        'flutter_gemma',
        'gemma-4-E2B-it.litertlm',
      );
      if (controller.modelPath.isEmpty && await File(candidate).exists()) {
        controller.configureModel(candidate);
      }
    }
    // Host-selected eager startup; preparation remains available lazily for
    // applications that cannot afford to retain an idle model.
    if (const bool.fromEnvironment(
      'OMNIX_EAGER_PREPARATION',
      defaultValue: true,
    )) {
      unawaited(controller.prepare());
    }
  }

  @override
  void dispose() {
    unawaited(
      _voice.close().catchError((Object e) => debugPrint('Voice close: $e')),
    );
    WidgetsBinding.instance.removeObserver(this);
    final models = _models;
    models?.dispose();
    if (models != null) unawaited(models.close());
    final controller = _controller;
    final knowledge = _knowledge;
    knowledge?.dispose();
    controller?.dispose();
    if (controller != null) {
      unawaited(
        controller
            .close()
            .whenComplete(() => knowledge?.close())
            .catchError((Object e) => debugPrint('Core close: $e')),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SelectableText('Home unavailable: ${snapshot.error}'),
        );
      }
      if (snapshot.connectionState != ConnectionState.done ||
          _controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final controller = _controller!;
      return ShowcaseShell(
        home: HomeChatPanel(
          controller: controller,
          pickAttachment: pickChatAttachment,
          voiceCapture: _voice,
        ),
        history: ChatHistoryPanel(controller: controller),
        pages: [
          (_) => CoreScreen(
            controller: controller,
            models: _models,
            drafts: StructuredDraftScreen(core: controller),
          ),
          (_) => KnowledgeExampleScreen(
            controller: _knowledge,
            models: _models,
            onUseInHome:
                (_knowledge?.backend as NativeKnowledgeDemoBackend?)
                        ?.rootIndexing ==
                    true
                ? _useKnowledgeInHome
                : null,
          ),
          (_) => const DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'Nodes · public fixtures'),
                    Tab(text: 'Devices · qualification'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [NexusExampleScreen(), MatterHostScreen()],
                  ),
                ),
              ],
            ),
          ),
          (_) => const StorageScreen(),
          (_) => const WorkflowScreen(),
        ],
      );
    },
  );
}
