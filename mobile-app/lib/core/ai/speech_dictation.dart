import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// App-wide speech dictation. Only one field can listen at a time.
class SpeechDictation extends ChangeNotifier {
  SpeechDictation._();
  static final SpeechDictation instance = SpeechDictation._();

  final SpeechToText _engine = SpeechToText();

  bool _ready = false;
  bool listening = false;
  String? activeFieldId;
  String lastWords = '';
  String? error;

  bool get isListening => listening;

  Future<bool> ensureReady() async {
    error = null;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      error = 'Microphone access is needed to talk instead of typing.';
      notifyListeners();
      return false;
    }
    if (_ready && _engine.isAvailable) return true;
    _ready = await _engine.initialize(
      onStatus: (status) {
        listening = _engine.isListening;
        if (status == 'done' || status == 'notListening') {
          listening = false;
          activeFieldId = null;
        }
        notifyListeners();
      },
      onError: (e) {
        listening = false;
        activeFieldId = null;
        error = e.errorMsg == 'error_speech_timeout'
            ? 'Didn’t catch that — tap the mic and try again.'
            : 'Couldn’t hear you. Check the microphone and try again.';
        notifyListeners();
      },
    );
    if (!_ready) {
      error = 'Speech isn’t available on this device. Try a physical phone.';
      notifyListeners();
    }
    return _ready;
  }

  Future<void> start({
    required String fieldId,
    required void Function(String words, bool isFinal) onWords,
  }) async {
    if (listening) await stop();
    final ok = await ensureReady();
    if (!ok) return;
    activeFieldId = fieldId;
    listening = true;
    lastWords = '';
    notifyListeners();
    await _engine.listen(
      onResult: (result) {
        lastWords = result.recognizedWords;
        onWords(result.recognizedWords, result.finalResult);
        notifyListeners();
      },
      localeId: 'en_US',
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        autoPunctuation: true,
        pauseFor: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> stop() async {
    if (_engine.isListening) await _engine.stop();
    listening = false;
    activeFieldId = null;
    notifyListeners();
  }

  Future<void> cancel() async {
    if (_engine.isListening) await _engine.cancel();
    listening = false;
    activeFieldId = null;
    notifyListeners();
  }

  bool isActive(String fieldId) => listening && activeFieldId == fieldId;
}
