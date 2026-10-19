import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../utils/text_formatters.dart';

/// App-wide speech dictation. Only one field can listen at a time.
///
/// The session stays open while the user is speaking. It ends when they
/// pause, or when they tap the mic off. A platform time limit restarts
/// the recognizer and keeps the text already spoken.
class SpeechDictation extends ChangeNotifier {
  SpeechDictation._();
  static final SpeechDictation instance = SpeechDictation._();

  static const Duration _pauseToEnd = Duration(seconds: 2);

  final SpeechToText _engine = SpeechToText();

  bool _ready = false;
  bool listening = false;
  String? activeFieldId;
  String lastWords = '';
  String? error;

  bool _sessionWanted = false;
  DateTime? _lastHeard;
  DateTime? _segmentStarted;
  void Function(String words, bool isFinal)? _onWords;
  String? _fieldId;
  /// Finished sentences for this tap, already capitalized and punctuated.
  String _closed = '';
  /// Words from the recognizer segment that is still open.
  String _open = '';

  bool get isListening => listening;

  Future<bool> ensureReady() async {
    error = null;
    if (_ready && _engine.isAvailable) return true;
    _ready = await _engine.initialize(
      onStatus: (status) {
        listening = _engine.isListening;
        if (status == 'done' || status == 'notListening') {
          listening = false;
          if (_sessionWanted) {
            _resumeIfCutOff();
          } else {
            activeFieldId = null;
          }
        }
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[Speech] ${e.errorMsg} permanent=${e.permanent}');
        final timeout = e.errorMsg == 'error_speech_timeout' ||
            e.errorMsg == 'error_no_match';
        if (_sessionWanted && timeout) {
          listening = false;
          _resumeIfCutOff();
          notifyListeners();
          return;
        }
        listening = false;
        _sessionWanted = false;
        activeFieldId = null;
        error = _messageFor(e.errorMsg);
        notifyListeners();
      },
    );
    if (!_ready) {
      final mic = await Permission.microphone.status;
      error = mic.isGranted
          ? 'Speech recognition is unavailable here. It needs a physical iPhone with Microphone and Speech Recognition allowed.'
          : 'Microphone access is needed to talk instead of typing.';
      notifyListeners();
    }
    return _ready;
  }

  String _messageFor(String code) {
    switch (code) {
      case 'error_permission':
      case 'error_speech_recognizer_disabled':
        return 'Allow Microphone and Speech Recognition for SRVBOARD, then try the mic again.';
      case 'error_network':
      case 'error_network_timeout':
        return 'Speech recognition needs a network connection. Check the connection and try again.';
      case 'error_listen_failed':
      case 'error_audio':
      case 'error_client':
        return 'The microphone could not start. On a simulator, allow Microphone for Simulator in Mac settings. On a phone, allow the microphone for SRVBOARD.';
      default:
        return 'Couldn’t hear you. Check the microphone and try again.';
    }
  }

  void _resumeIfCutOff() {
    if (!_sessionWanted || _onWords == null || _fieldId == null) {
      _finishSession();
      return;
    }
    final heard = _lastHeard;
    final paused = heard == null ||
        DateTime.now().difference(heard) >= _pauseToEnd;
    if (paused) {
      _sealOpen(closingPeriod: true);
      _finishSession();
      return;
    }
    // The platform ended the task on its own timer while the user was
    // still talking. Keep the words unpunctuated and listen again.
    _carryOpen();
    Future<void>.delayed(const Duration(milliseconds: 180), () async {
      if (!_sessionWanted || _onWords == null) return;
      await _beginListen();
    });
  }

  void _appendOpen() {
    final chunk = _open.trim();
    if (chunk.isEmpty) return;
    _closed = _closed.isEmpty ? chunk : '$_closed $chunk';
    _open = '';
  }

  /// Platform timer expired mid-sentence. Keep the words and do not
  /// insert a period yet.
  void _carryOpen() {
    _appendOpen();
    lastWords = _preview(closingPeriod: false);
    _onWords?.call(lastWords, false);
  }

  void _sealOpen({required bool closingPeriod}) {
    _appendOpen();
    if (_closed.isEmpty) return;
    final sentence =
        formatProfessionalNotes(_closed, closingPeriod: closingPeriod);
    _closed = sentence;
    lastWords = sentence;
    _onWords?.call(sentence, true);
  }

  String _preview({required bool closingPeriod}) {
    final live = _open.trim();
    final joined = live.isEmpty
        ? _closed
        : (_closed.isEmpty ? live : '$_closed $live');
    if (joined.trim().isEmpty) return joined;
    return formatProfessionalNotes(joined, closingPeriod: closingPeriod);
  }

  void _finishSession() {
    _sessionWanted = false;
    listening = false;
    activeFieldId = null;
    notifyListeners();
  }

  Future<void> start({
    required String fieldId,
    required void Function(String words, bool isFinal) onWords,
  }) async {
    if (listening || _sessionWanted) await stop();
    final ok = await ensureReady();
    if (!ok) return;
    _fieldId = fieldId;
    activeFieldId = fieldId;
    _onWords = onWords;
    _sessionWanted = true;
    _closed = '';
    _open = '';
    lastWords = '';
    _lastHeard = null;
    listening = true;
    notifyListeners();
    await _beginListen();
  }

  bool _starting = false;

  Future<void> _beginListen() async {
    if (!_sessionWanted || _onWords == null || _starting) return;
    _starting = true;
    try {
      if (_engine.isListening) {
        await _engine.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!_sessionWanted || _onWords == null) return;
      listening = true;
      activeFieldId = _fieldId;
      _segmentStarted = DateTime.now();
      notifyListeners();
      await _engine.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) _lastHeard = DateTime.now();
          _open = words;
          final started = _segmentStarted;
          final hitPlatformLimit = started != null &&
              DateTime.now().difference(started) >=
                  const Duration(seconds: 25);
          if (result.finalResult && hitPlatformLimit) {
            _carryOpen();
          } else if (result.finalResult) {
            _sealOpen(closingPeriod: true);
          } else {
            lastWords = _preview(closingPeriod: false);
            _onWords?.call(lastWords, false);
          }
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          pauseFor: _pauseToEnd,
          // iOS ends the recognizer near one minute. A longer window
          // starts the audio engine in a bad state and crashes.
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      debugPrint('[Speech] listen failed: $e');
      error = 'Speech isn’t available right now. Try again.';
      _finishSession();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _sealOpen(closingPeriod: true);
    _sessionWanted = false;
    if (_engine.isListening) await _engine.stop();
    listening = false;
    activeFieldId = null;
    _onWords = null;
    _fieldId = null;
    notifyListeners();
  }

  Future<void> cancel() async {
    _sessionWanted = false;
    if (_engine.isListening) await _engine.cancel();
    listening = false;
    activeFieldId = null;
    _onWords = null;
    _fieldId = null;
    notifyListeners();
  }

  bool isActive(String fieldId) =>
      _sessionWanted && activeFieldId == fieldId;
}
