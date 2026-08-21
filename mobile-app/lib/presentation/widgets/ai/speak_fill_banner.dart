import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ai/speech_dictation.dart';
import '../../../core/ai/spoken_parser.dart';

/// One-tap dictation that parses a sentence into a [SpokenDraft].
class SpeakFillBanner extends StatefulWidget {
  const SpeakFillBanner({
    super.key,
    required this.onDraft,
    this.hint = 'Tap, then say a name, company, address, or pay',
  });

  final ValueChanged<SpokenDraft> onDraft;
  final String hint;

  @override
  State<SpeakFillBanner> createState() => _SpeakFillBannerState();
}

class _SpeakFillBannerState extends State<SpeakFillBanner> {
  static const _id = 'speak-fill-banner';
  String _heard = '';

  SpeechDictation get _speech => SpeechDictation.instance;

  @override
  void initState() {
    super.initState();
    _speech.addListener(_tick);
  }

  @override
  void dispose() {
    _speech.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_speech.isActive(_id)) {
      await _speech.stop();
      _commit(_heard);
      return;
    }
    _heard = '';
    await _speech.start(
      fieldId: _id,
      onWords: (words, isFinal) {
        _heard = words;
        if (isFinal) _commit(words);
      },
    );
    if (mounted && _speech.error != null && !_speech.listening) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_speech.error!)),
      );
    }
  }

  void _commit(String words) {
    final draft = parseSpokenDraft(words);
    if (draft.isEmpty) return;
    widget.onDraft(draft);
  }

  @override
  Widget build(BuildContext context) {
    final active = _speech.isActive(_id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.23, 1, 0.32, 1),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: active
                ? const Color(0x1AEF4444)
                : const Color(0x1F4A90E2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? const Color(0x55EF4444)
                  : const Color(0x334A90E2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF4A90E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Listening… tap to stop' : 'Speak to fill',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF1A2130),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      active && _heard.isNotEmpty ? _heard : widget.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5C6778),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
