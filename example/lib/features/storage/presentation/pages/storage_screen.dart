import 'package:flutter/material.dart';
import 'package:omnix_example/app/feature_section.dart';
import 'package:omnix_example/features/storage/data/repositories/snapshot_repository.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final _note = TextEditingController();
  final _repository = SnapshotRepository();
  String _status =
      'Write a note, reopen the database, then restart the app to verify persistence.';
  bool _busy = false;
  Future<void> _run({required bool write}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final value = await _repository.reopen(note: write ? _note.text : null);
      if (mounted) {
        if (value != null) {
          _note.text = value;
        }
        setState(
          () => _status = value == null
              ? 'No saved note yet.'
              : 'Recovered from a fresh native SQLite connection.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FeatureSection(
            title: 'Persistent note',
            icon: Icons.storage_outlined,
            children: [
              const Text(
                'Save a note locally and reopen it to verify persistence. This is separate from Home chat history.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLines: 5,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Persistent note'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _run(write: true),
                    child: const Text('Save and reopen'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(write: false),
                    child: const Text('Read saved note'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(_status),
            ),
          ),
        ],
      ),
    ),
  );
}
