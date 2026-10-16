import 'dart:async';
import 'package:flutter/material.dart';
import 'package:omnix/omnix.dart' show OmnixAutonomyMode;
import '../controllers/core_controller.dart';

class ConversationControls extends StatelessWidget {
  const ConversationControls({super.key, required this.controller});
  final CoreController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller,
      if (controller.knowledge != null) controller.knowledge!,
    ]),
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.supportsAgent)
          SwitchListTile(
            title: const Text('Tools in all conversations'),
            subtitle: Text(
              controller.agentAvailable
                  ? 'App-wide setting. Use tools and skills when helpful; action approvals still apply.'
                  : 'This backend does not support a host-tool agent.',
            ),
            value: controller.agentEnabled,
            onChanged: !controller.agentAvailable || !controller.canSwitchAgent
                ? null
                : (enabled) => unawaited(controller.switchAgent(enabled)),
          ),
        if (controller.agentEnabled && controller.supportsAutonomy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<OmnixAutonomyMode>(
              key: ValueKey(controller.autonomy),
              initialValue: controller.autonomy,
              decoration: const InputDecoration(
                labelText: 'Autonomy',
                helperText:
                    'Choose before the first message. OS permissions still apply.',
                helperMaxLines: 2,
              ),
              items: const [
                DropdownMenuItem(
                  value: OmnixAutonomyMode.scopedAssistance,
                  child: Text('Scoped assistance'),
                ),
                DropdownMenuItem(
                  value: OmnixAutonomyMode.reviewEveryCall,
                  child: Text('Review every call'),
                ),
              ],
              onChanged:
                  controller.busy ||
                      controller.messages.isNotEmpty ||
                      controller.selectedId != null
                  ? null
                  : (mode) {
                      if (mode != null) {
                        controller.configureAutonomy(mode);
                      }
                    },
            ),
          ),
        if (controller.agentEnabled)
          if (controller.supportsEmailDrafts)
            CheckboxListTile(
              title: const Text('Allow email draft proposals'),
              subtitle: const Text(
                'Opt-in. Review each draft before opening your mail app. Never sends automatically.',
              ),
              value: controller.emailDraftsEnabled,
              onChanged:
                  controller.busy ||
                      controller.messages.isNotEmpty ||
                      controller.selectedId != null
                  ? null
                  : (value) => controller.configureEmailDrafts(value!),
            ),
        if (controller.agentEnabled)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Native agent chats can retain text, voice and images. Start a new chat to change tool options.',
            ),
          ),
        if (controller.supportsKnowledge)
          CheckboxListTile(
            dense: true,
            title: const Text('Answer from Knowledge'),
            subtitle: Text(
              controller.knowledge!.indexed
                  ? 'Text questions only. Retrieved sources are saved with the chat.'
                  : 'Open Knowledge and index a passage first.',
            ),
            value: controller.useKnowledge,
            onChanged:
                controller.busy ||
                    controller.messages.isNotEmpty ||
                    controller.selectedId != null
                ? null
                : (value) => controller.configureKnowledge(value!),
          ),
        if (controller.temporaryMediaChat)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Temporary media chat — not saved to history. Start a new chat to change input types.',
            ),
          ),
      ],
    ),
  );
}
