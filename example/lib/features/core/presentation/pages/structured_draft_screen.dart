import 'package:flutter/material.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/data/services/chat_attachment_picker.dart';
import 'package:omnix_example/features/core/domain/structured_draft.dart';
import 'package:omnix_example/features/core/presentation/widgets/structured_draft_panel.dart';

class StructuredDraftScreen extends StatefulWidget {
  const StructuredDraftScreen({super.key, required this.core});
  final CoreController core;
  @override
  State<StructuredDraftScreen> createState() => _StructuredDraftScreenState();
}

class _StructuredDraftScreenState extends State<StructuredDraftScreen> {
  final _backend = NativeStructuredDraftBackend();
  @override
  Widget build(BuildContext context) => StructuredDraftPanel(
    core: widget.core,
    backend: _backend,
    chooseAudio: () => pickChatAttachment(audioOnly: true),
  );
}
