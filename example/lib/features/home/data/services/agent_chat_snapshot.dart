import 'dart:convert';

import 'package:omnix/omnix.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';

// Host-owned presentation metadata. Native Rust validates the opaque context;
// these displayed entries never feed the model or dispatch historical actions.
final class AgentChatSnapshot {
  AgentChatSnapshot({
    required this.id,
    required this.title,
    required this.model,
    required this.instructions,
    required this.email,
    required this.autonomy,
    required this.checkpoint,
    required this.entries,
    this.maxOutputTokens = 256,
    this.sampling,
    this.contextTokens = 4096,
    this.images = false,
    this.audio = false,
    this.toolsEnabled = true,
  });
  final String id;
  final String title;
  final String model;
  final String instructions;
  final bool email;
  final OmnixAutonomyMode autonomy;
  final String checkpoint;
  final List<ChatEntry> entries;
  final int maxOutputTokens;
  final OmnixCoreSamplingOptions? sampling;
  final int contextTokens;
  final bool images;
  final bool audio;
  final bool toolsEnabled;

  String encode() => jsonEncode({
    'schemaVersion': 1,
    'record': {
      'id': id,
      'title': title,
      'modelPath': model,
      'kind': 'agent',
      'agentVersion': 1,
      'maxOutputTokens': maxOutputTokens,
      'sampling': sampling == null ? null : jsonDecode(sampling!.encode()),
      'contextTokens': contextTokens,
      'images': images,
      'audio': audio,
      'toolsEnabled': toolsEnabled,
      'systemPrompt': instructions,
      'emailDrafts': email,
      'autonomy': autonomy.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'checkpoint': checkpoint,
    'messages': [
      for (final e in entries)
        {
          'role': e.role,
          'text': e.text.isEmpty && e.attachments.isNotEmpty
              ? '[${e.attachments.map((a) => a.name).join(', ')}]'
              : e.text,
          'sources': [
            for (final s in e.sources)
              {'title': s.title, 'content': s.content, 'score': s.score},
          ],
          'activities': [
            for (final a in e.activities)
              {
                'tool': a.toolName,
                'state': a.state.name,
                'status': a.outcomeStatus,
                'reason': a.reason,
              },
          ],
          // Historical drafts remain evidence, not freshly actionable proposals.
        },
    ],
  });

  factory AgentChatSnapshot.decode(String snapshot) {
    if (snapshot.length > 24 * 1024 * 1024) {
      throw const FormatException('Agent snapshot too large.');
    }
    final value = jsonDecode(snapshot) as Map<String, dynamic>;
    final record = value['record'] as Map<String, dynamic>;
    final messages = value['messages'] as List;
    final checkpoint = value['checkpoint'];
    final instructions = record['systemPrompt'];
    final mode = record['autonomy'];
    // Before configurable budgets, all saved agent contexts used 256 tokens.
    final outputTokens = record['maxOutputTokens'] ?? 256;
    final contextTokens = record['contextTokens'] ?? 4096;
    if (contextTokens is! int ||
        contextTokens < 1024 ||
        contextTokens > 32768) {
      throw const FormatException('Invalid saved context window.');
    }
    final sampling = record['sampling'] == null
        ? null
        : OmnixCoreSamplingOptions.fromJson(
            record['sampling'] as Map<String, dynamic>,
          );
    if (outputTokens is! int ||
        outputTokens < 1 ||
        outputTokens > 4096 ||
        outputTokens > contextTokens ||
        value['schemaVersion'] != 1 ||
        record['kind'] != 'agent' ||
        record['agentVersion'] != 1 ||
        checkpoint is! String ||
        checkpoint.isEmpty ||
        checkpoint.length > 20 * 1024 * 1024 ||
        (record['images'] != null && record['images'] is! bool) ||
        (record['audio'] != null && record['audio'] is! bool) ||
        (record['toolsEnabled'] != null && record['toolsEnabled'] is! bool) ||
        instructions is! String ||
        instructions.length > 2000 ||
        record['id'] is! String ||
        (record['id'] as String).isEmpty ||
        record['title'] is! String ||
        record['modelPath'] is! String ||
        (record['modelPath'] as String).isEmpty ||
        messages.isEmpty ||
        messages.length > 10000 ||
        messages.length.isOdd ||
        !['scopedAssistance', 'reviewEveryCall'].contains(mode) ||
        record['emailDrafts'] is! bool) {
      throw const FormatException('Invalid agent snapshot.');
    }
    final entries = <ChatEntry>[];
    for (final item in messages) {
      final e = item as Map<String, dynamic>;
      final role = entries.length.isEven ? 'user' : 'assistant';
      if (e['role'] != role || e['text'] is! String) {
        throw const FormatException('Invalid agent transcript.');
      }
      final activities = e['activities'] as List;
      if (activities.length > 32 ||
          activities.any((a) => a['state'] == 'running')) {
        throw const FormatException('Incomplete saved tool activity.');
      }
      entries.add(
        ChatEntry(
          role,
          e['text'] as String,
          const [],
          [
            for (final s in e['sources'] as List)
              KnowledgePassage(
                s['title'] as String,
                s['content'] as String,
                (s['score'] as num?)?.toDouble(),
              ),
          ],
          [
            for (final a in activities)
              AgentActivity(
                a['tool'] as String,
                AgentActivityState.values.byName(a['state'] as String),
                outcomeStatus: a['status'] as String?,
                reason: a['reason'] as String?,
              ),
          ],
        ),
      );
    }
    return AgentChatSnapshot(
      id: record['id'] as String,
      title: record['title'] as String,
      model: record['modelPath'] as String,
      instructions: instructions,
      email: record['emailDrafts'] as bool,
      autonomy: mode == 'reviewEveryCall'
          ? OmnixAutonomyMode.reviewEveryCall
          : OmnixAutonomyMode.scopedAssistance,
      checkpoint: checkpoint,
      entries: List.unmodifiable(entries),
      maxOutputTokens: outputTokens,
      sampling: sampling,
      contextTokens: contextTokens,
      images: record['images'] as bool? ?? false,
      audio: record['audio'] as bool? ?? false,
      toolsEnabled: record['toolsEnabled'] as bool? ?? true,
    );
  }
}
