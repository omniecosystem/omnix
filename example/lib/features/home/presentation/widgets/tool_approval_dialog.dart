import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class ToolApprovalDialog extends StatelessWidget {
  const ToolApprovalDialog({
    super.key,
    required this.toolName,
    required this.arguments,
    required this.onAllow,
    required this.onDeny,
  });
  final String toolName;
  final String arguments;
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Allow $toolName?'),
    content: SingleChildScrollView(
      child: Text(
        'Allow this call once. This does not grant future access or override device permissions.\n\n$arguments',
      ),
    ),
    actions: [
      TextButton(onPressed: onDeny, child: const Text('Deny')),
      FilledButton(onPressed: onAllow, child: const Text('Allow once')),
    ],
  );
}

@Preview(name: 'One-call tool approval', group: 'Home')
Widget toolApprovalPreview() => MaterialApp(
  home: Scaffold(
    body: ToolApprovalDialog(
      toolName: 'host_time',
      arguments: '{}',
      onAllow: () {},
      onDeny: () {},
    ),
  ),
);
