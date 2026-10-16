import 'package:flutter/material.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({super.key, required this.controller});
  final CoreController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      children: [
        const ListTile(title: Text('Chat history')),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New chat'),
          enabled: !controller.busy,
          onTap: () => controller.select(null),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: controller.history.length,
            itemBuilder: (context, index) {
              final record = controller.history[index];
              return ListTile(
                title: Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: !controller.busy,
                selected: record.id == controller.selectedId,
                onTap: () => controller.select(record),
              );
            },
          ),
        ),
      ],
    ),
  );
}
