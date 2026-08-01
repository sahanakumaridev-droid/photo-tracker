import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Durable "latest attempt snapshot" for poor-network recovery.
///
/// Freezes location + capture timestamps at snapshot time so reconnect never
/// substitutes the user's current GPS/time. Only the newest snapshot is kept.
class AttemptSnapshotStore {
  AttemptSnapshotStore._();

  static const _prefsKey = 'attempt_snapshot_v1';
  static const _dirName = 'attempt_snapshots';

  /// Persist [payload] and copy [photoFiles] into app documents.
  /// Existing snapshot photos are replaced.
  static Future<Map<String, dynamic>> save({
    required Map<String, dynamic> payload,
    required List<File> photoFiles,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await _snapshotDir();
    // Wipe prior snapshot images so we don't leak disk.
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
      'photoPaths': persistedPaths,
      'frozenLocation': true,
      'snapshotAt': DateTime.now().toUtc().toIso8601String(),
      'source': payload['source'] ?? 'poor_network',
    };

    await prefs.setString(_prefsKey, jsonEncode(snapshot));
    return snapshot;
  }

  static Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await _snapshotDir();
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
    return prefs.remove(_prefsKey);
  }

  static Future<bool> hasSnapshot() async => (await read()) != null;

  static Future<Directory> _snapshotDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$_dirName');
  }
}
