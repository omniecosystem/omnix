import 'package:flutter/material.dart';
import 'package:omnix_example/features/core/presentation/widgets/conversation_controls.dart';
import 'package:omnix_example/features/core/presentation/pages/core_screen.dart';
import 'package:omnix_example/features/home/presentation/widgets/typing_dots.dart';
import 'core_controller_test.dart' show PreparationBackend;
import 'package:omnix/omnix.dart' show OmnixAutonomyMode;
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/presentation/widgets/home_chat_panel.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/home/domain/voice_capture.dart';

class FakeCapture implements VoiceCapture {
  int starts = 0;
  int cancels = 0;
  bool denied = false;
  Uint8List? bytes;
  @override
  Future<void> start() async {
    if (denied) throw StateError('Microphone permission denied');
    starts++;
  }

  @override
  Future<ChatAttachment> stop() async => ChatAttachment(
    'Voice message.wav',
    OmnixInputPart.audio(bytes ?? Uint8List.fromList([1, 2])),
  );
  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> close() async {}
}

class MediaBackend extends FakeBackend implements MediaCoreBackend {
  List<ChatAttachment> received = [];
  String? receivedPrompt;
  @override
  Stream<String> generateMessage(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) {
    received = attachments;
    receivedPrompt = prompt;
    return Stream.value('Image received');
  }
}

class FakeBackend implements CoreDemoBackend {
  @override
  Stream<String> generate(String model, String prompt) =>
      Stream.fromIterable(['One ', 'continuous answer.']);
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

class AgentBackend extends FakeBackend
    implements AgentProgressBackend, AgentAutonomyBackend {
  @override
  OmnixAutonomyMode autonomy = OmnixAutonomyMode.scopedAssistance;
  @override
  void configureAutonomy(OmnixAutonomyMode mode) {
    autonomy = mode;
  }

  @override
  bool agentEnabled = false;
  @override
  bool get agentAvailable => true;
  @override
  String get agentText => '';
  @override
  String? agentStatus;
  @override
  void configureAgent(bool enabled) {
    agentEnabled = enabled;
  }
}

class SwitchingBackend extends AgentBackend implements LiveAgentCoreBackend {
  bool reject = false;
  bool closed = false;
  Completer<void>? gate;
  @override
  bool get canSwitchAgent => true;
  @override
  Future<void> switchAgent(bool enabled, String model) async {
    await gate?.future;
    if (reject) throw StateError('Cannot change capabilities');
    agentEnabled = enabled;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  testWidgets('Home accepts a prompt while loading and shows waiting dots', (
    tester,
  ) async {
    final backend = PreparationBackend();
    final controller = CoreController(backend)..configureModel('model');
    final preparing = controller.prepare();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: controller)),
      ),
    );
    expect(find.text('Model ready'), findsNothing);
    expect(find.byTooltip('Conversation options'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Hello while loading');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('Hello while loading'), findsOneWidget);
    expect(find.byType(TypingDots), findsOneWidget);
    expect(backend.generations, 0);
    backend.gate.complete();
    await preparing;
    await tester.pumpAndSettle();
    expect(find.text('Text reply'), findsOneWidget);
    expect(find.byType(TypingDots), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });

  testWidgets('voice recording remains available while model prepares', (
    tester,
  ) async {
    final backend = PreparationBackend();
    final controller = CoreController(backend)..configureModel('model');
    final preparing = controller.prepare();
    final voice = FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeChatPanel(controller: controller, voiceCapture: voice),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    expect(voice.starts, 1);
    await tester.tap(find.text('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.text('Voice message.wav'), findsOneWidget);
    expect(controller.messages, isEmpty);
    backend.gate.complete();
    await preparing;
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });

  testWidgets('Core exposes tools and autonomy controls instead of Home', (
    tester,
  ) async {
    final controller = CoreController(AgentBackend())..configureModel('model');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoreScreen(controller: controller)),
      ),
    );
    await tester.ensureVisible(find.text('Tools in all conversations'));
    await tester.tap(find.text('Tools in all conversations'));
    await tester.pumpAndSettle();
    expect(controller.agentEnabled, isTrue);
    expect(find.text('Scoped assistance'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });

  test(
    'controller close waits for a capability change and blocks concurrent sends',
    () async {
      final backend = SwitchingBackend();
      final controller = CoreController(backend)
        ..configureModel('gemma.litertlm');
      await controller.send('gemma.litertlm', 'First');
      backend.gate = Completer<void>();
      final change = controller.switchAgent(true);
      expect(controller.busy, isTrue);
      expect(controller.canSwitchAgent, isFalse);
      final transcript = List.of(controller.messages);
      await controller.send('gemma.litertlm', 'No overlapping turn');
      expect(controller.messages, transcript);
      final closing = controller.close();
      await Future<void>.delayed(Duration.zero);
      expect(backend.closed, isFalse);
      backend.gate!.complete();
      await change;
      await closing;
      expect(backend.closed, isTrue);
      controller.dispose();
    },
  );
  testWidgets(
    'Home switches tools after completed text while keeping the transcript',
    (tester) async {
      final backend = SwitchingBackend();
      final controller = CoreController(backend)
        ..configureModel('gemma.litertlm');
      await controller.send('gemma.litertlm', 'Remember this');
      final transcript = List.of(controller.messages);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationControls(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tools in all conversations'));
      await tester.pumpAndSettle();
      expect(backend.agentEnabled, isTrue);
      expect(controller.messages, transcript);
      await tester.tap(find.text('Tools in all conversations'));
      await tester.pumpAndSettle();
      expect(backend.agentEnabled, isFalse);
      expect(controller.messages, transcript);
      backend.reject = true;
      await tester.tap(find.text('Tools in all conversations'));
      await tester.pumpAndSettle();
      expect(backend.agentEnabled, isFalse);
      expect(controller.error, contains('Cannot change capabilities'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('image voice and text share one draft and one send', (
    tester,
  ) async {
    final backend = MediaBackend();
    final controller = CoreController(backend)
      ..configureModel('gemma.litertlm');
    final voice = FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeChatPanel(
            controller: controller,
            voiceCapture: voice,
            pickAttachment: () async => ChatAttachment(
              'scene.jpg',
              OmnixInputPart.image(Uint8List.fromList([1, 2])),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Attach image or WAV'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Explain what I am pointing at',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    expect(find.text('scene.jpg'), findsOneWidget);
    expect(controller.messages, isEmpty);
    await tester.tap(find.text('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.text('Voice message.wav'), findsOneWidget);
    expect(controller.messages, isEmpty);
    final mic = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.mic),
    );
    expect(mic.onPressed, isNull);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(backend.receivedPrompt, 'Explain what I am pointing at');
    expect(backend.received.map((a) => a.part.kind), [
      OmnixInputKind.image,
      OmnixInputKind.audio,
    ]);
    expect(controller.messages.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
  testWidgets('oversized recording preserves image draft without sending', (
    tester,
  ) async {
    final controller = CoreController(MediaBackend())
      ..configureModel('gemma.litertlm');
    final voice = FakeCapture()..bytes = Uint8List(2 * 1024 * 1024 + 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeChatPanel(
            controller: controller,
            voiceCapture: voice,
            pickAttachment: () async => ChatAttachment(
              'scene.jpg',
              OmnixInputPart.image(Uint8List.fromList([1])),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Attach image or WAV'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Audio must be under 2 MiB'), findsOneWidget);
    expect(find.text('scene.jpg'), findsOneWidget);
    expect(find.text('Voice message.wav'), findsNothing);
    expect(controller.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
  testWidgets(
    'autonomy can be selected before a turn but not during a conversation',
    (tester) async {
      final backend = AgentBackend()..agentEnabled = true;
      final controller = CoreController(backend)..modelPath = 'model';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationControls(controller: controller),
            ),
          ),
        ),
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<OmnixAutonomyMode>),
        findsOneWidget,
      );
      expect(find.text('Scoped assistance'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<OmnixAutonomyMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review every call').last);
      await tester.pumpAndSettle();
      expect(backend.autonomy, OmnixAutonomyMode.reviewEveryCall);
      await controller.send('model', 'Hello');
      controller.configureAutonomy(OmnixAutonomyMode.scopedAssistance);
      await tester.pump();
      expect(backend.autonomy, OmnixAutonomyMode.reviewEveryCall);
      final dropdown = tester
          .widget<DropdownButtonFormField<OmnixAutonomyMode>>(
            find.byType(DropdownButtonFormField<OmnixAutonomyMode>),
          );
      expect(dropdown.onChanged, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('Home attaches expandable activity to its completed answer', (
    tester,
  ) async {
    final controller = CoreController(FakeBackend())
      ..modelPath = 'model'
      ..messages = [
        const ChatEntry('user', 'Reset?'),
        const ChatEntry('assistant', 'Press reset.', [], [], [
          AgentActivity('search_knowledge', AgentActivityState.completed),
        ]),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: controller)),
      ),
    );
    expect(find.text('Press reset.'), findsOneWidget);
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Search local Knowledge'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Press reset.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('Home renders tool progress separately from answer text', (
    tester,
  ) async {
    final backend = AgentBackend()
      ..agentEnabled = true
      ..agentStatus = 'Searching local Knowledge';
    final controller = CoreController(backend)
      ..configureModel('gemma.litertlm');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: controller)),
      ),
    );
    expect(find.text('Searching local Knowledge'), findsOneWidget);
    backend.agentStatus = null;
    controller.configureAgent(true);
    await tester.pump();
    expect(find.text('Searching local Knowledge'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'Home explicitly enables agent and explains text and media history',
    (tester) async {
      final backend = AgentBackend();
      final controller = CoreController(backend)
        ..configureModel('gemma.litertlm');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationControls(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tools in all conversations'));
      await tester.pumpAndSettle();
      expect(backend.agentEnabled, isTrue);
      expect(
        find.textContaining('Native agent chats can retain'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'compact Home keeps options off the composer and works with a keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CoreController(AgentBackend()..agentEnabled = true)
        ..modelPath = 'model';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HomeChatPanel(controller: controller)),
        ),
      );
      expect(find.text('Agent'), findsNothing);
      expect(find.byTooltip('Conversation options'), findsNothing);
      expect(find.text('Model ready'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Allow email draft proposals'), findsNothing);
      expect(
        find.textContaining('Native agent chats can retain'),
        findsNothing,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'recording stops at 55 seconds; backgrounding discards the next capture',
    (tester) async {
      final controller = CoreController(MediaBackend())
        ..configureModel('gemma.litertlm');
      final voice = FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeChatPanel(controller: controller, voiceCapture: voice),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 55));
      await tester.pumpAndSettle();
      expect(find.text('Stop recording'), findsNothing);
      expect(find.byType(InputChip), findsOneWidget);
      expect(controller.messages, isEmpty);
      await tester.tap(find.byTooltip('Remove attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(voice.cancels, greaterThanOrEqualTo(1));
      expect(find.byType(InputChip), findsNothing);
      expect(controller.messages, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      controller.dispose();
    },
  );
  testWidgets(
    'empty composer records, stops to a draft and sends only on confirmation',
    (tester) async {
      final backend = MediaBackend();
      final controller = CoreController(backend)
        ..configureModel('gemma.litertlm');
      final voice = FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeChatPanel(controller: controller, voiceCapture: voice),
          ),
        ),
      );
      expect(find.byTooltip('Record voice message'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.text('Send'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pumpAndSettle();
      expect(voice.starts, 1);
      expect(find.text('Stop recording'), findsOneWidget);
      expect(controller.messages, isEmpty);
      await tester.tap(find.text('Stop recording'));
      await tester.pumpAndSettle();
      expect(find.text('Voice message.wav'), findsOneWidget);
      expect(controller.messages, isEmpty);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(backend.received.single.part.kind, OmnixInputKind.audio);
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      controller.dispose();
    },
  );
  testWidgets('cancel and microphone denial do not send a message', (
    tester,
  ) async {
    final controller = CoreController(MediaBackend())
      ..configureModel('gemma.litertlm');
    final voice = FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeChatPanel(controller: controller, voiceCapture: voice),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel recording'));
    await tester.pumpAndSettle();
    expect(voice.cancels, 1);
    expect(find.byType(InputChip), findsNothing);
    voice.denied = true;
    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Microphone permission denied'), findsOneWidget);
    expect(controller.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
  testWidgets(
    'picker cancellation preserves draft; attachment-only send is temporary',
    (tester) async {
      final backend = MediaBackend();
      final controller = CoreController(backend)
        ..configureModel('gemma.litertlm');
      ChatAttachment? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeChatPanel(
              controller: controller,
              pickAttachment: () async => selection,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.tap(find.byTooltip('Attach image or WAV'));
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      expect(controller.messages, isEmpty);
      selection = ChatAttachment(
        'red.png',
        OmnixInputPart.image(Uint8List.fromList([1])),
      );
      await tester.tap(find.byTooltip('Attach image or WAV'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(backend.received.single.name, 'red.png');
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Image received'), findsOneWidget);
      expect(find.text('Media · temporary chat'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      controller.dispose();
    },
  );

  testWidgets('attachments can be removed and picker failures remain visible', (
    tester,
  ) async {
    final controller = CoreController(MediaBackend())
      ..configureModel('gemma.litertlm');
    bool fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeChatPanel(
            controller: controller,
            pickAttachment: () async {
              if (fail) throw StateError('File unavailable');
              return ChatAttachment(
                'audio.wav',
                OmnixInputPart.audio(Uint8List.fromList([1])),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Attach image or WAV'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    fail = true;
    await tester.tap(find.byTooltip('Attach image or WAV'));
    await tester.pumpAndSettle();
    expect(find.textContaining('File unavailable'), findsOneWidget);
    expect(controller.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
  testWidgets('sends a prompt and renders deltas as one selectable answer', (
    tester,
  ) async {
    final controller = CoreController(FakeBackend());
    controller.configureModel('trusted.litertlm');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: controller)),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'Hello');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('One continuous answer.'), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
}
