import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  const codec = OmnixWorkflowCodec();

  group('OmnixWorkflowCodec', () {
    test('round-trips a task through the versioned representation', () {
      final task = OmnixWorkflowTask(
        id: 'task-1',
        kind: 'summarize',
        title: 'Summarize',
        description: 'A document',
        input: const {
          'documentId': 'document-1',
          'options': {'brief': true},
        },
        status: OmnixWorkflowTaskStatus.running,
        attempt: 1,
        maxAttempts: 3,
        createdAt: DateTime.parse('2026-09-21T12:00:00+02:00'),
        updatedAt: DateTime.parse('2026-09-21T12:01:00+02:00'),
      );

      final encoded = codec.encodeTask(task);
      final decoded = codec.decodeTask(encoded);

      expect(encoded['schemaVersion'], OmnixWorkflowCodec.schemaVersion);
      expect(decoded.id, task.id);
      expect(decoded.input, task.input);
      expect(decoded.status, task.status);
      expect(decoded.createdAt, DateTime.utc(2026, 9, 21, 10));
      expect(decoded.updatedAt, DateTime.utc(2026, 9, 21, 10, 1));
    });

    test('round-trips an event with structured data', () {
      final event = OmnixWorkflowEvent(
        taskId: 'task-1',
        kind: OmnixWorkflowEventKind.progress,
        timestamp: DateTime.utc(2026, 9, 21),
        message: 'Loaded skill.',
        data: const {
          'skill': 'browse_the_web',
          'sources': ['https://example.com'],
        },
      );

      final decoded = codec.decodeEvent(codec.encodeEvent(event));

      expect(decoded.taskId, event.taskId);
      expect(decoded.kind, event.kind);
      expect(decoded.message, event.message);
      expect(decoded.data, event.data);
    });

    test('rejects unknown schema versions and enum values', () {
      final task = _validTaskJson();

      expect(
        () => codec.decodeTask({...task, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => codec.decodeTask({...task, 'status': 'paused'}),
        throwsFormatException,
      );
    });

    test('rejects invalid counters and non-JSON values', () {
      expect(
        () => codec.decodeTask({..._validTaskJson(), 'attempt': 3}),
        throwsFormatException,
      );
      final task = OmnixWorkflowTask(
        id: 'task-1',
        kind: 'test',
        title: 'Invalid input',
        input: {'object': Object()},
        status: OmnixWorkflowTaskStatus.queued,
        attempt: 0,
        maxAttempts: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(() => codec.encodeTask(task), throwsFormatException);
    });
  });
}

Map<String, Object?> _validTaskJson() => {
  'schemaVersion': 1,
  'id': 'task-1',
  'kind': 'test',
  'title': 'Test',
  'description': null,
  'input': <String, Object?>{},
  'status': 'queued',
  'attempt': 0,
  'maxAttempts': 1,
  'createdAt': '2026-09-21T00:00:00.000Z',
  'updatedAt': '2026-09-21T00:00:00.000Z',
  'output': null,
  'error': null,
};
