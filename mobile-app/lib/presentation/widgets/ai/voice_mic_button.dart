import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ai/speech_dictation.dart';

enum VoiceFillMode { replace, append }

/// Compact mic that fills [controller] from speech. Tap to talk, tap to stop.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.mode = VoiceFillMode.replace,
    this.color = const Color(0xFF4A90E2),
    this.tooltip = 'Tap to talk',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoiceFillMode mode;
  final Color color;
  final String tooltip;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  late final String _id =
      'field-${identityHashCode(widget.controller)}';
  String _base = '';

  SpeechDictation get _speech => SpeechDictation.instance;

  @override
  void initState() {
    super.initState();
    _speech.addListener(_onSpeech);
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeech);
    super.dispose();
  }

  void _onSpeech() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_speech.isActive(_id)) {
      await _speech.stop();
      return;
    }
    _base = widget.controller.text;
    await _speech.start(
      fieldId: _id,
      onWords: (words, _) {
        if (!mounted || words.trim().isEmpty) return;
        final next = widget.mode == VoiceFillMode.replace
            ? words.trim()
            : _join(_base, words);
        widget.controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        widget.onChanged?.call(next);
      },
    );
    if (mounted && _speech.error != null && !_speech.listening) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_speech.error!)),
      );
    }
  }

  String _join(String base, String words) {
    final a = base.trim();
    final b = words.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a $b';
  }

  @override
  Widget build(BuildContext context) {
    final active = _speech.isActive(_id);
    return Tooltip(
      message: active ? 'Listening… tap to stop' : widget.tooltip,
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.23, 1, 0.32, 1),
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFEF4444)
                : widget.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
            size: 18,
            color: active ? Colors.white : widget.color,
          ),
        ),
      ),
    );
  }
}

/// Mic plus an optional extra suffix (clear / filter) for search fields.
class VoiceSuffix extends StatelessWidget {
  const VoiceSuffix({
    super.key,
    required this.controller,
    this.extra,
    this.onChanged,
    this.mode = VoiceFillMode.replace,
  });

  final TextEditingController controller;
  final Widget? extra;
  final ValueChanged<String>? onChanged;
  final VoiceFillMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VoiceMicButton(
          controller: controller,
          onChanged: onChanged,
          mode: mode,
        ),
        if (extra != null) extra!,
      ],
    );
  }
}
