import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';

/// Network quality for attempt caching under poor signal.
///
/// Detects offline + high-latency (probe RTT). Upload screens subscribe and
/// continually snapshot attempt inputs while [isPoor] is true.
class NetworkQualityService {
  NetworkQualityService._();
  static final NetworkQualityService instance = NetworkQualityService._();

  /// RTT above this (or probe failure) counts as poor network.
  static const Duration poorLatencyThreshold = Duration(milliseconds: 2500);
  static const Duration probeInterval = Duration(seconds: 12);
  static const Duration probeTimeout = Duration(seconds: 8);

  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<ConnectivityResult>? _connSub;
  Timer? _probeTimer;
  bool _initialized = false;
  bool _isPoor = false;
  int? _lastRttMs;

  bool get isPoor => _isPoor;
  int? get lastRttMs => _lastRttMs;

  /// Emits whenever poor/good flips.
  Stream<bool> get onPoorChanged => _controller.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final conn = await Connectivity().checkConnectivity();
      await _recompute(conn == ConnectivityResult.none);
    } catch (_) {
      await _recompute(true);
    }
    _connSub = Connectivity().onConnectivityChanged.listen((result) {
      unawaited(_recompute(result == ConnectivityResult.none));
    });
    _probeTimer = Timer.periodic(probeInterval, (_) {
      unawaited(_recompute(false));
    });
  }

  Future<void> _recompute(bool forceOffline) async {
    var poor = forceOffline;
    if (!forceOffline) {
      try {
        final conn = await Connectivity().checkConnectivity();
        if (conn == ConnectivityResult.none) {
          poor = true;
          _lastRttMs = null;
        } else {
          final rtt = await _probeRtt();
          _lastRttMs = rtt;
          poor = rtt == null || rtt >= poorLatencyThreshold.inMilliseconds;
        }
      } catch (_) {
        poor = true;
        _lastRttMs = null;
      }
    } else {
      _lastRttMs = null;
    }
    if (poor != _isPoor) {
      _isPoor = poor;
      if (!_controller.isClosed) _controller.add(poor);
      debugPrint(
          '[NetworkQuality] poor=$poor rttMs=${_lastRttMs ?? 'n/a'}');
    } else {
      _isPoor = poor;
    }
  }

  /// Lightweight GET against the API root / companies list.
  Future<int?> _probeRtt() async {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient()..connectionTimeout = probeTimeout;
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/companies');
      final req = await client.getUrl(uri).timeout(probeTimeout);
      final res = await req.close().timeout(probeTimeout);
      await res.drain<void>();
      client.close(force: true);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sw.stop();
      return null;
    }
  }

  /// Force an immediate probe (e.g. after Quick Save).
  Future<bool> checkNow() async {
    await _recompute(false);
    return _isPoor;
  }

  void dispose() {
    _probeTimer?.cancel();
    _connSub?.cancel();
    _controller.close();
  }
}
