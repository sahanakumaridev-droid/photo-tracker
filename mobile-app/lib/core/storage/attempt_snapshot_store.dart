import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Durable local cache of in-progress attempts (Quick Save / Save & Exit /
/// poor-network auto-save), keyed by [id] so multiple attempts can be cached
/// at once instead of one clobbering the next.
///
/// Freezes location + capture timestamps at snapshot time so reconnect never
/// substitutes the user's current GPS/time. Callers own the [id]: existing
/// server attempts key off their server id, brand-new attempts get a
/// client-generated id that stays stable for the life of that draft session
/// (see `AttemptDraftController.snapshotId`) so repeated saves of the same
/// attempt update the same slot rather than piling up duplicates.
class AttemptSnapshotStore {
  AttemptSnapshotStore._();

  static const _indexKey = 'attempt_snapshot_index_v1';
  static const _dirName = 'attempt_snapshots';

  /// Persist [payload] under [id] and copy [photoFiles] into app documents.
  /// Photos previously saved under this same [id] are replaced.
  static Future<Map<String, dynamic>> save({
    required String id,
    required Map<String, dynamic> payload,
    required List<File> photoFiles,
  }) async {
    final dir = await _snapshotDir(id);
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        try {
          f.deleteSync(recursive: true);
        } catch (_) {}
      }
    } else {
      dir.createSync(recursive: true);
    }

    final persistedPaths = <String>[];
    for (var i = 0; i < photoFiles.length; i++) {
      final src = photoFiles[i];
      if (!src.existsSync()) continue;
      final ext = src.path.contains('.')
          ? src.path.substring(src.path.lastIndexOf('.'))
          : '.jpg';
      final dest = File('${dir.path}/${const Uuid().v4()}$ext');
      await src.copy(dest.path);
      persistedPaths.add(dest.path);
    }

    final snapshot = {
      ...payload,
      'snapshotId': id,
      'photoPaths': persistedPaths,
      'frozenLocation': true,
      'snapshotAt': DateTime.now().toUtc().toIso8601String(),
      'source': payload['source'] ?? 'poor_network',
    };

    final index = await _readIndex();
    index[id] = jsonEncode(snapshot);
    await _writeIndex(index);
    return snapshot;
  }

  /// All cached snapshots, newest first.
  static Future<List<Map<String, dynamic>>> readAll() async {
    final index = await _readIndex();
    final out = <Map<String, dynamic>>[];
    for (final raw in index.values) {
      try {
        out.add(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    out.sort((a, b) => (b['snapshotAt'] as String? ?? '')
        .compareTo(a['snapshotAt'] as String? ?? ''));
    return out;
  }

  static Future<Map<String, dynamic>?> read(String id) async {
    final index = await _readIndex();
    final raw = index[id];
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> clear(String id) async {
    final dir = await _snapshotDir(id);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
    final index = await _readIndex();
    final removed = index.remove(id) != null;
    await _writeIndex(index);
    return removed;
  }

  static Future<Directory> _snapshotDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$_dirName/$id');
  }

  static Future<Map<String, String>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeIndex(Map<String, String> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }
}
