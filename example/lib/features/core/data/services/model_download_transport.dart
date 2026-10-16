import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:path/path.dart' as p;

import 'package:omnix_example/features/core/data/services/background_model_transfer.dart';

final class NativeModelInstallationPort implements ModelInstallationPort {
  NativeModelInstallationPort(this.installer);
  final OmnixModelInstaller installer;
  @override
  Future<List<OmnixInstalledModel>> installed() => installer.installed();
  @override
  Future<List<OmnixTransferReservation>> pending() =>
      installer.pendingTransfers();
  @override
  Future<OmnixTransferReservation> reserve(OmnixModelSpec spec) =>
      installer.reserveTransfer(spec);
  @override
  Future<OmnixInstalledModel> complete(String id) =>
      installer.completeTransfer(id);
}

DownloadTask modelDownloadTask(
  OmnixTransferReservation reservation,
  String url,
  String? token,
  BaseDirectory base,
  String directory,
) => DownloadTask(
  taskId: modelTaskId(reservation.id),
  url: url,
  filename: reservation.spec.filename,
  directory: directory,
  baseDirectory: base,
  group: modelTransferGroup,
  updates: Updates.statusAndProgress,
  headers: {
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  },
  // HF weak validators are not safe to promise resume against in this version.
  allowPause: Uri.parse(url).host != 'huggingface.co',
  // Android 14+ selects UIDT; older platforms use configured foreground work.
  priority: 0,
  retries: 3,
  metaData: reservation.id,
  displayName: reservation.spec.filename,
);

final class PluginModelTransferPort implements ModelTransferPort {
  final FileDownloader downloader = FileDownloader();
  Future<void>? _ready;
  @override
  Future<void> initialize() => _ready ??= _initialize();

  Future<void> _initialize() async {
    downloader.registerCallbacks(
      group: modelTransferGroup,
      taskStatusCallback: (_) {},
      taskProgressCallback: (_) {},
    );
    downloader.configureNotificationForGroup(
      modelTransferGroup,
      running: const TaskNotification(
        'Downloading model',
        '{filename} · {progress}',
      ),
      error: const TaskNotification('Model download interrupted', '{filename}'),
      progressBar: true,
      tapOpensFile: false,
    );
    if (Platform.isAndroid) {
      // This example owns its downloader configuration; Core does not touch it.
      await downloader.configure(
        androidConfig: [(Config.runInForeground, Config.always)],
      );
    }
    // A reservation starts as an EMPTY file. Presence must never imply completion.
    await downloader.trackTasksInGroup(
      modelTransferGroup,
      markDownloadedComplete: false,
    );
    await downloader.resumeFromBackground();
  }

  @override
  Future<bool> enqueue(
    OmnixTransferReservation reservation,
    String url,
    String? token,
  ) async {
    if (Platform.isAndroid) {
      await downloader.permissions.request(PermissionType.notifications);
    }
    final (base, directory, _) = await Task.split(filePath: reservation.path);
    final resolved = base == BaseDirectory.root
        ? p.dirname(reservation.path)
        : directory;
    return downloader.enqueue(
      modelDownloadTask(reservation, url, token, base, resolved),
    );
  }

  @override
  Future<TaskRecord?> record(String id) async {
    final record = await downloader.database.recordForId(id);
    return record?.group == modelTransferGroup ? record : null;
  }

  @override
  Future<void> cancel(String id) async {
    await downloader.cancelTaskWithId(id);
  }

  @override
  Future<void> forget(String id) => downloader.database.deleteRecordWithId(id);
  @override
  Future<bool> resume(String id) async {
    final task = (await record(id))?.task;
    if (task is! DownloadTask || !await downloader.taskCanResume(task)) {
      return false;
    }
    return downloader.resume(task);
  }
}
