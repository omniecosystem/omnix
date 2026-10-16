import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/device_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/agent-host');
  final calls = <String>[];
  final tools = const ExampleDeviceTools(channel: channel).tools;
  OmnixToolRequest request(String name, Map<String, dynamic> arguments) =>
      OmnixToolRequest.fromJson({
        'requestId': 'test-1',
        'toolName': name,
        'arguments': arguments,
      });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'deviceInfo'
              ? {'model': 'test-device', 'androidApi': 31}
              : {'status': 'denied'};
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('read-only device tool forwards host facts', () async {
    expect(
      await tools
          .singleWhere((tool) => tool.name == 'host_device_info')
          .execute(request('host_device_info', {})),
      {'model': 'test-device', 'androidApi': 31},
    );
    expect(calls, ['deviceInfo']);
  });
  group('native workflow tools', () {
    final battery = tools.singleWhere(
      (tool) => tool.name == 'host_battery_status',
    );
    final share = tools.singleWhere((tool) => tool.name == 'host_share_text');
    test(
      'battery forwards real host receipt without invented values',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'batteryStatus');
              return {
                'status': 'succeeded',
                'percent': 62,
                'charging': true,
                'report': 'Battery: 62%, charging.',
              };
            });
        expect(
          (await battery.execute(request(battery.name, {})) as Map)['report'],
          'Battery: 62%, charging.',
        );
      },
    );
    test('invalid share input never reaches Android', () async {
      for (final args in [
        <String, dynamic>{},
        {'text': ''},
        {'text': ' '},
        {'text': 42},
        {'text': 'x' * 4001},
        {'text': 'report', 'engineAuthorized': true},
      ]) {
        final receipt = await share.execute(request(share.name, args)) as Map;
        expect(receipt['status'], 'invalid_arguments');
        expect(receipt['executionStarted'], false);
      }
      expect(calls, isEmpty);
    });
    test(
      'authorized share forwards saved text and confirms only handoff',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'shareText');
              expect(call.arguments, {
                'text': 'Battery: 62%, charging.',
                'engineAuthorized': true,
              });
              return {'status': 'editor_opened'};
            });
        final authorized = const ExampleDeviceTools(
          channel: channel,
          engineAuthorized: true,
        ).workflowTools;
        final tool = authorized.singleWhere((tool) => tool.name == share.name);
        expect(
          await tool.execute(
            request(tool.name, {'text': 'Battery: 62%, charging.'}),
          ),
          {'status': 'editor_opened'},
        );
        expect(
          (tool.parameters['properties'] as Map).containsKey(
            'engineAuthorized',
          ),
          false,
        );
      },
    );
    test('share refusal is not promoted to success', () async {
      expect(await share.execute(request(share.name, {'text': 'report'})), {
        'status': 'denied',
      });
      expect(calls, ['shareText']);
    });
    test(
      'workflow settings receipt is normalized without claiming changes',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => {'status': 'opened'},
            );
        final tool = const ExampleDeviceTools(
          channel: channel,
        ).workflowTools.singleWhere((tool) => tool.name == 'host_open_app');
        expect(
          await tool.execute(request(tool.name, {'application': 'settings'})),
          {
            'status': 'succeeded',
            'handoff': 'settings_opened',
            'settingsChanged': false,
          },
        );
      },
    );
  });
  test('arbitrary applications never reach the platform', () async {
    final result = await tools.last.execute(
      request('host_open_app', {'application': 'com.example.bank'}),
    );
    expect((result as Map)['status'], 'denied');
    expect(calls, isEmpty);
  });
  test('settings request preserves host refusal, not success', () async {
    expect(
      await tools.last.execute(
        request('host_open_app', {'application': 'settings'}),
      ),
      {'status': 'denied'},
    );
    expect(calls, ['openSettings']);
  });
  test('host confirmation success is preserved', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {'status': 'opened'});
    expect(
      await tools.last.execute(
        request('host_open_app', {'application': 'settings'}),
      ),
      {'status': 'opened'},
    );
  });
  test('stop asks the host to dismiss pending approval', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    await const ExampleDeviceTools(channel: channel).cancelPending();
    expect(calls, ['cancelPending']);
  });

  test(
    'policy-authorized settings handoff does not request a second review',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'openSettings');
            expect(call.arguments, {'engineAuthorized': true});
            return {'status': 'opened'};
          });
      final authorized = const ExampleDeviceTools(
        channel: channel,
        engineAuthorized: true,
      ).tools;
      expect(
        await authorized.last.execute(
          request('host_open_app', {'application': 'settings'}),
        ),
        {'status': 'opened'},
      );
      expect(authorized.last.parameters['additionalProperties'], false);
      expect(
        (authorized.last.parameters['properties'] as Map).containsKey(
          'engineAuthorized',
        ),
        false,
      );
    },
  );

  test('standalone settings adapter retains native review', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          return {'status': 'denied'};
        });
    await tools.last.execute(
      request('host_open_app', {'application': 'settings'}),
    );
  });

  group('calendar editor handoff', () {
    final calendar = tools.singleWhere(
      (tool) => tool.name == 'host_prepare_calendar_event',
    );
    Map<String, dynamic> proposal() => {
      'title': ' Team meeting ',
      'start': '2026-10-12T10:00:00+02:00',
      'end': '2026-10-12T11:00:00+02:00',
      'location': '',
      'description': 'Review the roadmap',
    };
    test(
      'policy-authorized calendar retains validation and skips duplicate review',
      () async {
        final authorized = const ExampleDeviceTools(
          channel: channel,
          engineAuthorized: true,
        ).tools.singleWhere((t) => t.name == calendar.name);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'prepareCalendarEvent');
              expect(call.arguments['engineAuthorized'], true);
              expect(call.arguments['title'], 'Team meeting');
              return {'status': 'editor_opened'};
            });
        expect(await authorized.execute(request(calendar.name, proposal())), {
          'status': 'editor_opened',
        });
        final forged =
            await authorized.execute(
                  request(calendar.name, {
                    ...proposal(),
                    'engineAuthorized': true,
                  }),
                )
                as Map;
        expect(forged['status'], 'invalid_arguments');
      },
    );
    test(
      'optional metadata is omitted from required schema and defaults to empty',
      () async {
        expect(calendar.parameters['required'], ['title', 'start', 'end']);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.arguments['location'], '');
              expect(call.arguments['description'], '');
              return {'status': 'editor_opened'};
            });
        final args = proposal()
          ..remove('location')
          ..remove('description');
        expect(await calendar.execute(request(calendar.name, args)), {
          'status': 'editor_opened',
        });
      },
    );
    test(
      'passes bounded proposal with absolute times, not a saved claim',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'prepareCalendarEvent');
              expect(call.arguments, {
                'title': 'Team meeting',
                'location': '',
                'description': 'Review the roadmap',
                'startMillis': DateTime.utc(
                  2026,
                  10,
                  12,
                  8,
                ).millisecondsSinceEpoch,
                'endMillis': DateTime.utc(
                  2026,
                  10,
                  12,
                  9,
                ).millisecondsSinceEpoch,
              });
              return {'status': 'editor_opened'};
            });
        expect(await calendar.execute(request(calendar.name, proposal())), {
          'status': 'editor_opened',
        });
      },
    );
    for (final status in ['denied', 'unavailable', 'failed']) {
      test('preserves $status outcome', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => {'status': status});
        expect(await calendar.execute(request(calendar.name, proposal())), {
          'status': status,
        });
      });
    }
    final invalid = <Map<String, dynamic>>[
      {'start': '2026-10-12T10:00:00'},
      {'start': '2026-02-30T10:00:00Z'},
      {'start': '2026-10-12T25:00:00Z'},
      {'start': '2026-10-12T10:00:00+15:00'},
      {'end': '2026-10-12T08:00:00Z'},
      {'end': '2026-11-12T08:00:00Z'},
      {'title': ''},
      {'description': null},
      {'extra': 'unexpected'},
    ];
    for (var i = 0; i < invalid.length; i++) {
      test('rejects malformed proposal $i before any host action', () async {
        final result = await calendar.execute(
          request(calendar.name, {...proposal(), ...invalid[i]}),
        );
        expect((result as Map)['status'], 'invalid_arguments');
        expect(calls, isEmpty);
      });
    }
    test('rejects oversized text', () async {
      final result = await calendar.execute(
        request(calendar.name, {
          ...proposal(),
          'title': List.filled(201, 'x').join(),
        }),
      );
      expect((result as Map)['status'], 'invalid_arguments');
      expect(calls, isEmpty);
    });
    test('date diagnostics name the field without echoing its value', () async {
      final result =
          await calendar.execute(
                request(calendar.name, {
                  ...proposal(),
                  'start': 'private invalid date',
                }),
              )
              as Map;
      expect(result['reason'], contains('start must be'));
      expect(result['reason'], isNot(contains('private invalid date')));
      expect(calls, isEmpty);
    });
    test('optional metadata does not make required title optional', () async {
      final args = proposal()..remove('title');
      final result =
          await calendar.execute(request(calendar.name, args)) as Map;
      expect(result['status'], 'invalid_arguments');
      expect(result['reason'], contains('title must be'));
      expect(calls, isEmpty);
    });
  });
}
