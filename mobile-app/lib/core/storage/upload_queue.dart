import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Lifecycle of a queued upload.
///   draft     — saved by the user, not yet submitted
///   pending   — submitted, waiting for a network window
///   retrying  — actively being (re)uploaded right now
///   uploaded  — succeeded (entry is then removed from the box)
///   failed    — exceeded retry budget; kept for manual retry
enum QueuedStatus { draft, pending, retrying, uploaded, failed }

/// A single photo upload, persisted so it survives app switches / kills and a
/// total loss of signal. CRITICAL: [takenAt] (original capture time) and the
/// [latitude]/[longitude] geotag are captured once and never regenerated — the
/// retry re-sends exactly what was captured in the field.
class QueuedUpload {
  QueuedUpload({
    required this.id,
    required this.filePath,
    required this.profileId,
    required this.latitude,
    required this.longitude,
    required this.takenAt,
    required this.createdAt,
    this.address,
    this.note,
    this.category,
    this.completionType,
    this.servedTo,
    this.relationTo,
    this.fileNumber,
    this.successful = false,
    this.attemptStatus = 'pending',
    this.payRate,
    this.locationGroupId,
    this.userId,
    this.profileName,
    this.status = QueuedStatus.pending,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String filePath; // persistent, already-watermarked image
  final int profileId;
  final double latitude;
  final double longitude;
  final String takenAt; // ISO-8601 — original capture time, never regenerated
  final String createdAt;
  final String? address;
  final String? note;
  final String? category;
  final String? completionType;
  final String? servedTo;
  final String? relationTo;
  final String? fileNumber;
  final bool successful;
  final String attemptStatus;
  final int? payRate;
  final int? locationGroupId;
  final int? userId;
  final String? profileName;
  QueuedStatus status;
  int attempts;
  String? lastError;

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'profileId': profileId,
        'latitude': latitude,
        'longitude': longitude,
        'takenAt': takenAt,
        'createdAt': createdAt,
        'address': address,
        'note': note,
        'category': category,
        'completionType': completionType,
        'servedTo': servedTo,
        'relationTo': relationTo,
        'fileNumber': fileNumber,
        'successful': successful,
        'attemptStatus': attemptStatus,
        'payRate': payRate,
        'locationGroupId': locationGroupId,
        'userId': userId,
        'profileName': profileName,
        'status': status.name,
        'attempts': attempts,
        'lastError': lastError,
      };

  static QueuedUpload fromMap(Map<dynamic, dynamic> m) {
    final successful = (m['successful'] as bool?) ?? false;
    final attemptStatus = (m['attemptStatus'] as String?) ??
        (successful ? 'successful' : 'unsuccessful');
    return QueuedUpload(
        id: m['id'] as String,
        filePath: m['filePath'] as String,
        profileId: m['profileId'] as int,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        takenAt: m['takenAt'] as String,
        createdAt: m['createdAt'] as String,
        address: m['address'] as String?,
        note: m['note'] as String?,
        category: m['category'] as String?,
        completionType: m['completionType'] as String?,
        servedTo: m['servedTo'] as String?,
        relationTo: m['relationTo'] as String?,
        fileNumber: m['fileNumber'] as String?,
        successful: successful,
        attemptStatus: attemptStatus,
        payRate: m['payRate'] as int?,
        locationGroupId: m['locationGroupId'] as int?,
        userId: m['userId'] as int?,
        profileName: m['profileName'] as String?,
        status: QueuedStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => QueuedStatus.pending,
        ),
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['lastError'] as String?,
      );
  }
}

/// Signature for the actual network upload. Returns normally on success and
/// throws on failure (network or server). Injected so the queue stays free of
/// any Dio/Riverpod dependency.
typedef Uploader = Future<void> Function(QueuedUpload item);

/// Persistent, auto-retrying upload queue for low-/no-signal field use.
///
/// - Entries persist in a Hive box (JSON) and watermarked images are copied to
///   a persistent app directory so they outlive the OS temp cache.
/// - Retries fire automatically when connectivity returns and on a periodic
///   timer while the app is foregrounded.
class UploadQueueService {
  UploadQueueService._();
  static final UploadQueueService instance = UploadQueueService._();

  static const _boxName = 'upload_queue';
  static const _maxAttempts = 1000; // effectively "keep trying" in the field
  static const _retryInterval = Duration(seconds: 45);

  Box<String>? _box;
  Uploader? _uploader;
  Timer? _timer;
  StreamSubscription<dynamic>? _connSub;
  bool _processing = false;
  bool _paused = false;

  /// Live count of items not yet uploaded — drives any UI badge.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _refreshCount();
    // Retry whenever the device regains connectivity.
    _connSub = Connectivity().onConnectivityChanged.listen((_) => process());
    _timer = Timer.periodic(_retryInterval, (_) => process());
  }

  /// Wire the network uploader once Riverpod providers are available, then
  /// drain anything left over from a previous session.
  void attachUploader(Uploader uploader) {
    _uploader = uploader;
    process();
  }

  /// Pause the auto-drainer while a screen uploads items it JUST enqueued, in
  /// its own order (e.g. multi-photo grouping). The items stay persisted as
  /// `pending`, so a crash or app-kill mid-batch still auto-resumes on the next
  /// launch — but the queue won't race the screen's upload and double-send.
  /// Always pair with [resumeAutoProcess] in a `finally`.
  void pauseAutoProcess() => _paused = true;

  void resumeAutoProcess() {
    _paused = false;
    process();
  }

  List<QueuedUpload> get items {
    final box = _box;
    if (box == null) return const [];
    return box.values
        .map((s) => QueuedUpload.fromMap(
            jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _refreshCount() {
    pendingCount.value =
        items.where((i) => i.status != QueuedStatus.uploaded).length;
  }

  Future<void> _save(QueuedUpload item) async {
    await _box?.put(item.id, jsonEncode(item.toMap()));
    _refreshCount();
  }

  Future<void> _remove(QueuedUpload item) async {
    await _box?.delete(item.id);
    // Best-effort cleanup of the persisted image.
    try {
      final f = File(item.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _refreshCount();
  }

  /// Persist [sourceFile] (the already-watermarked image) into a durable
  /// directory and enqueue the upload. Returns the queued item.
  Future<QueuedUpload> enqueue({
    required File sourceFile,
    required int profileId,
    required double latitude,
    required double longitude,
    required String takenAt,
    String? address,
    String? note,
    String? category,
    String? completionType,
    String? servedTo,
    String? relationTo,
    String? fileNumber,
    bool successful = false,
    String attemptStatus = 'pending',
    int? payRate,
    int? locationGroupId,
    int? userId,
    String? profileName,
    QueuedStatus status = QueuedStatus.pending,
  }) async {
    final id = const Uuid().v4();
    final persistentPath = await _persist(sourceFile, id);
    final item = QueuedUpload(
      id: id,
      filePath: persistentPath,
      profileId: profileId,
      latitude: latitude,
      longitude: longitude,
      takenAt: takenAt,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      address: address,
      note: note,
      category: category,
      completionType: completionType,
      servedTo: servedTo,
      relationTo: relationTo,
      fileNumber: fileNumber,
      successful: successful,
      attemptStatus: attemptStatus,
      payRate: payRate,
      locationGroupId: locationGroupId,
      userId: userId,
      profileName: profileName,
      status: status,
    );
    await _save(item);
    // Kick a drain attempt immediately (no-op if offline / pending status).
    if (status == QueuedStatus.pending) unawaited(process());
    return item;
  }

  Future<String> _persist(File source, String id) async {
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/upload_queue');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.'))
        : '.png';
    final dest = File('${dir.path}/$id$ext');
    await source.copy(dest.path);
    return dest.path;
  }

  /// Promote a draft to pending so it joins the auto-retry loop.
  Future<void> markPending(String id) async {
    final item = _byId(id);
    if (item == null) return;
    item.status = QueuedStatus.pending;
    item.lastError = null;
    await _save(item);
    unawaited(process());
  }

  Future<void> remove(String id) async {
    final item = _byId(id);
    if (item != null) await _remove(item);
  }

  QueuedUpload? _byId(String id) {
    try {
      return items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Drain the queue: attempt each pending/failed item once. Safe to call
  /// often — it self-guards against overlapping runs and missing uploader.
  Future<void> process() async {
    final uploader = _uploader;
    final box = _box;
    if (uploader == null || box == null || _processing || _paused) return;
    _processing = true;
    try {
      // Only attempt when we believe we're online (connectivity_plus v5
      // reports a single ConnectivityResult).
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) return;

      for (final item in items) {
        if (item.status == QueuedStatus.uploaded ||
            item.status == QueuedStatus.draft) {
          continue;
        }
        item.status = QueuedStatus.retrying;
        await _save(item);
        try {
          await uploader(item);
          await _remove(item); // success — drop it
        } catch (e) {
          item.attempts += 1;
          item.lastError = e.toString().replaceAll('Exception: ', '');
          item.status = item.attempts >= _maxAttempts
              ? QueuedStatus.failed
              : QueuedStatus.pending;
          await _save(item);
        }
      }
    } finally {
      _processing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _connSub?.cancel();
  }
}
