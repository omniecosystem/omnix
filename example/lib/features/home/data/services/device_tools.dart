import 'package:flutter/services.dart';
import 'package:omnix/omnix.dart';

class ExampleDeviceTools {
  const ExampleDeviceTools({
    this.channel = const MethodChannel('xyz.omniecosystem.omnix/agent_host'),
    this.engineAuthorized = false,
  });

  final MethodChannel channel;
  final bool engineAuthorized;

  Future<void> cancelPending() => channel.invokeMethod<void>('cancelPending');

  List<OmnixHostTool> get tools => [
    OmnixHostTool(
      name: 'host_notify_text',
      description:
          'Post a local Android notification containing text. Reports posting, not that the user read it. Notifications must be permitted.',
      parameters: _schema(const {
        'text': {'type': 'string'},
      }),
      execute: (request) => channel.invokeMethod<Object?>('notifyText', {
        'text': request.arguments['text'],
        'receiptId': request.requestId,
      }),
    ),
    OmnixHostTool(
      name: 'host_device_info',
      description:
          'Read device manufacturer, model and Android API version. '
          'Does not read identifiers, files, location or accounts.',
      parameters: _schema(const {}),
      execute: (_) => channel.invokeMethod<Object?>('deviceInfo'),
    ),
    OmnixHostTool(
      name: 'host_battery_status',
      description:
          'Read Android battery percentage and charging state. Returns a report string for sharing. Read-only; no monitoring is installed.',
      parameters: _schema(const {}),
      execute: (_) => channel.invokeMethod<Object?>('batteryStatus'),
    ),
    OmnixHostTool(
      name: 'host_share_text',
      description:
          'Open Android share sheet with supplied text (1–4000 characters). The user chooses the recipient and sends in another app. editor_opened confirms handoff only, never delivery.',
      parameters: _schema(const {
        'text': {'type': 'string'},
      }),
      execute: (request) async {
        final text = request.arguments['text'];
        if (request.arguments.keys.any((key) => key != 'text') ||
            text is! String ||
            text.trim().isEmpty ||
            text.length > 4000) {
          return {
            'status': 'invalid_arguments',
            'reason': 'Expected nonblank text of at most 4000 characters.',
            'executionStarted': false,
          };
        }
        return channel.invokeMethod<Object?>('shareText', {
          'text': text,
          if (engineAuthorized) 'engineAuthorized': true,
        });
      },
    ),
    OmnixHostTool(
      name: 'host_prepare_calendar_event',
      description:
          'Open the calendar editor with a proposed event, subject to host policy. '
          'Supply title, start and end as ISO dates with explicit timezone '
          '(YYYY-MM-DDTHH:mm:ssZ or ±HH:mm), location and description '
          '(both optional; omit if unknown). Ask the user when date/time is unclear. '
          'Never claim the event was saved: editor_opened only means handoff.',
      parameters: _schema(
        const {
          'title': {'type': 'string'},
          'start': {'type': 'string'},
          'end': {'type': 'string'},
          'location': {'type': 'string'},
          'description': {'type': 'string'},
        },
        required: const ['title', 'start', 'end'],
      ),
      execute: (request) async {
        final args = request.arguments;
        final title = args['title'];
        final location = args.containsKey('location') ? args['location'] : '';
        final description = args.containsKey('description')
            ? args['description']
            : '';
        final start = _parseTime(args['start']);
        final end = _parseTime(args['end']);
        final issues = <String>[];
        if (args.keys.any(
          (key) => !const [
            'title',
            'start',
            'end',
            'location',
            'description',
          ].contains(key),
        )) {
          issues.add('Unexpected field(s)');
        }
        if (title is! String || title.trim().isEmpty || title.length > 200) {
          issues.add('title must be nonblank text of at most 200 characters');
        }
        if (location is! String || location.length > 500) {
          issues.add('location must be text of at most 500 characters');
        }
        if (description is! String || description.length > 2000) {
          issues.add('description must be text of at most 2000 characters');
        }
        if (start == null) {
          issues.add('start must be a valid explicit-zone ISO date');
        }
        if (end == null) {
          issues.add('end must be a valid explicit-zone ISO date');
        }
        if (start != null &&
            end != null &&
            (!end.isAfter(start) ||
                end.difference(start) > const Duration(days: 7))) {
          issues.add('end must follow start by at most seven days');
        }
        if (issues.isNotEmpty) {
          return {
            'status': 'invalid_arguments',
            'reason': '${issues.join('; ')}. No host action was executed.',
          };
        }
        return channel.invokeMethod<Object?>('prepareCalendarEvent', {
          if (engineAuthorized) 'engineAuthorized': true,
          'title': (title as String).trim(),
          'location': location,
          'description': description,
          'startMillis': start!.millisecondsSinceEpoch,
          'endMillis': end!.millisecondsSinceEpoch,
        });
      },
    ),
    OmnixHostTool(
      name: 'host_open_app',
      description:
          'Open Android Settings, subject to host policy. '
          'Only application=settings is supported. Never changes a setting. '
          'Report opened only when the host returns that status.',
      parameters: _schema(const {
        'application': {'type': 'string'},
      }),
      execute: (request) async {
        if (request.arguments['application'] != 'settings') {
          return {'status': 'denied', 'reason': 'Application is not allowed'};
        }
        return channel.invokeMethod<Object?>(
          'openSettings',
          engineAuthorized ? {'engineAuthorized': true} : null,
        );
      },
    ),
  ];

  // Recovery contracts belong to the consumer, not to model-generated plans.
  static const workflowRetryContracts = {
    'host_notify_text': 'RequiresReconciliation',
    'host_battery_status': 'SafeToRepeat',
    'host_share_text': 'RequiresReconciliation',
    'host_open_app': 'RequiresReconciliation',
  };

  List<OmnixHostTool> get workflowTools => tools
      .where((tool) => workflowRetryContracts.containsKey(tool.name))
      .map(
        (tool) => OmnixHostTool(
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters,
          execute: (request) async {
            final result = await tool.execute(request);
            // Settings' existing Home receipt uses `opened`. Normalize only this
            // known host handoff, not arbitrary tool status strings.
            if (tool.name == 'host_open_app' &&
                result is Map &&
                result['status'] == 'opened') {
              return {
                'status': 'succeeded',
                'handoff': 'settings_opened',
                'settingsChanged': false,
              };
            }
            return result;
          },
        ),
      )
      .toList();

  static DateTime? _parseTime(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final [year, month, day, hour, minute, second] = parts;
    if (year < 2000 || year > 2100 || hour > 23 || minute > 59 || second > 59) {
      return null;
    }
    final local = DateTime.utc(year, month, day, hour, minute, second);
    if (local.year != year || local.month != month || local.day != day) {
      return null;
    }
    final zone = match.group(7)!;
    if (zone != 'Z') {
      final hours = int.parse(zone.substring(1, 3));
      final minutes = int.parse(zone.substring(4, 6));
      if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
        return null;
      }
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static Map<String, Object?> _schema(
    Map<String, Object?> properties, {
    List<String>? required,
  }) => {
    'type': 'object',
    'properties': properties,
    'required': required ?? properties.keys.toList(),
    'additionalProperties': false,
  };
}
