import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/model_installation_types.dart';
import 'package:omnix_example/features/core/data/services/background_model_transfer.dart';
import 'package:omnix_example/features/core/data/services/model_download_transport.dart';

const spec = OmnixModelSpec(
  filename: 'test.litertlm',
  sha256: 'trusted',
  bytes: 100,
  role: 'chat',
);
const reservation = OmnixTransferReservation(
  id: 'a-b-c',
  spec: spec,
  path: '/app/models/.transfer-a-b-c/test.litertlm',
);

class InstallationFake implements ModelInstallationPort {
  List<OmnixInstalledModel> models = [];
  List<OmnixTransferReservation> reservations = [];
  bool reject = false;
  int reserves = 0;
  int completions = 0;
  @override
  Future<List<OmnixInstalledModel>> installed() async => models;
  @override
  Future<List<OmnixTransferReservation>> pending() async => reservations;
  @override
  Future<OmnixTransferReservation> reserve(OmnixModelSpec spec) async {
    reserves++;
    reservations = [reservation];
    return reservation;
  }

  @override
  Future<OmnixInstalledModel> complete(String id) async {
    completions++;
    if (reject) throw StateError('SHA-256 mismatch');
    final model = OmnixInstalledModel(
      spec: spec,
      path: '/app/models/verified/test.litertlm',
    );
    models = [model];
    reservations = [];
    return model;
  }
}

class TransferFake implements ModelTransferPort {
  bool tracked = true;
  TaskStatus status = TaskStatus.complete;
  TaskException? exception;
  int enqueues = 0;
  int cancellations = 0;
  int forgotten = 0;
  bool rejectCleanup = false;
  void Function()? onRecord;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> enqueue(
    OmnixTransferReservation reservation,
    String url,
    String? token,
  ) async {
    enqueues++;
    tracked = true;
    status = TaskStatus.complete;
    return true;
  }

  @override
  Future<TaskRecord?> record(String id) async {
    if (!tracked) return null;
    onRecord?.call();
    return TaskRecord(
      DownloadTask(
        taskId: id,
        url: 'https://example.invalid/model',
        group: modelTransferGroup,
      ),
      status,
      0.5,
      100,
      exception,
    );
  }

  @override
  Future<void> cancel(String id) async {
    cancellations++;
    status = TaskStatus.canceled;
  }

  @override
  Future<void> forget(String id) async {
    forgotten++;
    if (rejectCleanup) throw StateError('task database unavailable');
    tracked = false;
  }

  @override
  Future<bool> resume(String id) async => false;
}

void main() {
  late InstallationFake files;
  late TransferFake transport;
  late BackgroundModelTransfer service;
  setUp(() {
    files = InstallationFake();
    transport = TransferFake();
    service = BackgroundModelTransfer(
      files,
      transport,
      pollInterval: Duration.zero,
    );
  });
  test(
    'fresh download is verified through Rust port before publication',
    () async {
      transport.tracked = false;
      final updates = await service
          .download(spec, 'https://example.invalid/model', null)
          .toList();
      expect(files.reserves, 1);
      expect(transport.enqueues, 1);
      expect(files.completions, 1);
      expect(updates.map((e) => e.phase), ['verifying', 'installed']);
      expect(transport.forgotten, 1);
    },
  );
  test(
    'restart reconciles completed transfer without enqueueing again',
    () async {
      files.reservations = [reservation];
      final recovered = await service.recover();
      expect(recovered, isNotNull);
      expect((await recovered!.toList()).last.phase, 'installed');
      expect(transport.enqueues, 0);
    },
  );
  test(
    'failed verification retains reservation but permits fresh retry',
    () async {
      files.reservations = [reservation];
      files.reject = true;
      final recovered = await service.recover();
      await expectLater(recovered!.toList(), throwsStateError);
      expect(files.models, isEmpty);
      expect(files.reservations, isNotEmpty);
      expect(transport.forgotten, 1);
    },
  );
  test('detaching observation does not cancel OS task', () async {
    files.reservations = [reservation];
    transport.status = TaskStatus.running;
    final recovered = await service.recover();
    transport.onRecord = service.detach;
    await recovered!.toList();
    expect(transport.cancellations, 0);
    expect(files.completions, 0);
  });
  test(
    'restart surfaces a failed transfer without automatic download',
    () async {
      files.reservations = [reservation];
      transport.status = TaskStatus.failed;
      final updates = await (await service.recover())!.toList();
      expect(updates.single.phase, 'failed');
      expect(files.reservations, [reservation]);
      expect(files.completions, 0);
      expect(transport.enqueues, 0);
    },
  );
  test(
    'restart surfaces missing tracking without automatically retrying',
    () async {
      files.reservations = [reservation];
      transport.tracked = false;
      final updates = await (await service.recover())!.toList();
      expect(updates.single.phase, 'failed');
      expect(updates.single.error, contains('Retry explicitly'));
      expect(files.reservations, [reservation]);
      expect(transport.enqueues, 0);
    },
  );
  test('restart preserves cancellation and does not publish', () async {
    files.reservations = [reservation];
    transport.status = TaskStatus.canceled;
    final updates = await (await service.recover())!.toList();
    expect(updates.single.phase, 'cancelled');
    expect(files.completions, 0);
    expect(transport.enqueues, 0);
  });
  test(
    'cleanup failure does not turn verified installation into failure',
    () async {
      files.reservations = [reservation];
      transport.rejectCleanup = true;
      final updates = await (await service.recover())!.toList();
      expect(updates.last.phase, 'installed');
      expect(updates.last.path, files.models.single.path);
      expect(updates.last.error, contains('cleanup failed'));
      expect(files.reservations, isEmpty);
      expect(transport.enqueues, 0);
    },
  );
  test('cleanup failure preserves the original verification error', () async {
    files.reservations = [reservation];
    files.reject = true;
    transport.rejectCleanup = true;
    await expectLater(
      (await service.recover())!.toList(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'SHA-256 mismatch',
        ),
      ),
    );
    expect(files.models, isEmpty);
    expect(files.reservations, [reservation]);
  });
  test('HTTP authorization error stops retries without publishing', () async {
    files.reservations = [reservation];
    transport.status = TaskStatus.waitingToRetry;
    transport.exception = TaskHttpException('access denied', 403);
    final updates = await (await service.recover())!.toList();
    expect(updates.last.phase, 'failed');
    expect(transport.cancellations, 1);
    expect(files.completions, 0);
  });
  test('explicit retry reuses failed reservation identity', () async {
    files.reservations = [reservation];
    transport.status = TaskStatus.failed;
    await service
        .download(spec, 'https://example.invalid/model', null)
        .toList();
    expect(files.reserves, 0);
    expect(transport.enqueues, 1);
  });
  test('installed artifact is reused without download', () async {
    files.models = [const OmnixInstalledModel(spec: spec, path: '/ready')];
    expect(
      (await service
              .download(spec, 'https://example.invalid/model', null)
              .toList())
          .last
          .path,
      '/ready',
    );
    expect(transport.enqueues, 0);
  });
  test('HTTP URL is rejected before reservation or scheduling', () async {
    await expectLater(
      service.download(spec, 'http://example.invalid/model', null).toList(),
      throwsArgumentError,
    );
    expect(files.reserves, 0);
    expect(transport.enqueues, 0);
  });
  test(
    'task identity, scope, destination and HF resume policy are explicit',
    () {
      final task = modelDownloadTask(
        reservation,
        'https://huggingface.co/repo/resolve/pin/file',
        'test-token',
        BaseDirectory.root,
        r'C:\app\models\.transfer-a-b-c',
      );
      expect(task.taskId, modelTaskId(reservation.id));
      expect(task.group, modelTransferGroup);
      expect(task.directory, r'C:\app\models\.transfer-a-b-c');
      expect(task.filename, spec.filename);
      expect(task.allowPause, isFalse);
      expect(task.priority, 0);
      expect(task.updates, Updates.statusAndProgress);
      expect(task.metaData, reservation.id);
      expect(task.headers['Authorization'], 'Bearer test-token');
    },
  );
}
