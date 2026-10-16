import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix/omnix.dart' show OmnixEmailIntent;
import 'package:omnix_example/features/home/data/services/native_intent_host.dart'
    as host;

class NativeEmailIntentCard extends StatefulWidget {
  const NativeEmailIntentCard({
    super.key,
    required this.intent,
    this.openComposer,
  });
  final OmnixEmailIntent intent;
  final Future<bool> Function(Uri)? openComposer;
  @override
  State<NativeEmailIntentCard> createState() => _NativeEmailIntentCardState();
}

class _NativeEmailIntentCardState extends State<NativeEmailIntentCard> {
  bool _busy = false;
  bool _opened = false;
  bool _dismissed = false;
  String? _error;
  Future<void> _review() async {
    if (_busy || _opened || _dismissed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review email draft'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Opening your mail app shares this draft with that app. Nothing is sent automatically. Review it again there before sending.',
                ),
                const SizedBox(height: 16),
                SelectableText('To: ${widget.intent.recipient}'),
                SelectableText('Subject: ${widget.intent.subject}'),
                const Divider(),
                SelectableText(widget.intent.body),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open mail composer'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final uri = host.emailComposerUri(widget.intent);
      final opened =
          await (widget.openComposer?.call(uri) ??
              host.openEmailComposer(widget.intent));
      if (mounted) {
        setState(() {
          _opened = opened;
          _error = opened
              ? null
              : 'No mail composer was opened. Configure an email app or copy the draft manually.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open a mail composer. No email was sent.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dismissed
                ? 'Email draft dismissed'
                : 'Email draft · requires your approval',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!_dismissed) ...[
            SelectableText('To: ${widget.intent.recipient}'),
            SelectableText(widget.intent.subject),
            if (_opened)
              const Text(
                'Mail composer opened. Send status is unknown; confirm in your mail app.',
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : _review,
                    child: const Text('Review draft'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _dismissed = true),
                    child: const Text('Dismiss draft'),
                  ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ],
      ),
    ),
  );
}

@Preview(name: 'Native email proposal', size: Size(420, 260))
Widget nativeEmailProposalPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: NativeEmailIntentCard(
      intent: OmnixEmailIntent.fromJson({
        'kind': 'email',
        'recipient': 'alex@example.com',
        'subject': 'Meeting tomorrow',
        'body': 'Can we meet at ten?',
      }),
      openComposer: (_) async => false,
    ),
  ),
);
