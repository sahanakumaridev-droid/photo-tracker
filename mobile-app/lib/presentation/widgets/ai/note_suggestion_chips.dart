import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/note_phrases.dart';

/// Short labels. The stored note stays the exact phrase in [kUnsuccessfulNotePhrases].
const kNoteShortcutLabels = <String>[
  'No one home',
  'Noise, no answer',
  'No vehicle',
  'No lights',
  'Lights, no movement',
  'Gated community',
  'Key-fob building',
  'Waited at entrance',
  'Nobody let me in',
  'Called out, no answer',
];

/// Outcome-filtered attempt note shortcuts (exact DB string literals).
class NoteSuggestionChips extends StatefulWidget {
  const NoteSuggestionChips({
    super.key,
    required this.controller,
    this.onChanged,
    this.outcome,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;
  final String? outcome;

  @override
  State<NoteSuggestionChips> createState() => _NoteSuggestionChipsState();
}

class _NoteSuggestionChipsState extends State<NoteSuggestionChips> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.outcome == kAttemptStatusSuccessful) {
      return const SizedBox.shrink();
    }
    const phrases = kUnsuccessfulNotePhrases;
    final visible = _expanded ? phrases.length : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < visible && i < phrases.length; i++)
              _chip(
                kNoteShortcutLabels[i],
                phrases[i],
                widget.controller.text.contains(phrases[i]),
              ),
            if (!_expanded)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _expanded = true);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x1F4A90E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'More',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4A90E2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, String phrase, bool on) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final current = widget.controller.text.trim();
        final next = current.isEmpty
            ? phrase
            : current.contains(phrase)
                ? current
                : '$current $phrase';
        widget.controller.text = next;
        widget.controller.selection =
            TextSelection.collapsed(offset: next.length);
        widget.onChanged?.call();
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF1A2130) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : const Color(0xFF1A2130),
          ),
        ),
      ),
    );
  }
}

class SubjectDescriptionForm extends StatelessWidget {
  const SubjectDescriptionForm({
    super.key,
    required this.description,
    required this.onChanged,
  });

  final SubjectDescription description;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _line('Gender', description.gender, (v) {
          description.gender = v;
          onChanged();
        }),
        _line('Ethnicity', description.ethnicity, (v) {
          description.ethnicity = v;
          onChanged();
        }),
        _line('Age', description.age, (v) {
          description.age = v;
          onChanged();
        }),
        _line('Height', description.height, (v) {
          description.height = v;
          onChanged();
        }),
        _line('Weight', description.weight, (v) {
          description.weight = v;
          onChanged();
        }),
        _line('Hair Color', description.hairColor, (v) {
          description.hairColor = v;
          onChanged();
        }),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Tattoos/Piercing',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          value: description.tattoosPiercing,
          onChanged: (v) {
            description.tattoosPiercing = v;
            onChanged();
          },
        ),
      ],
    );
  }

  Widget _line(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: value,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF2F4F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE3E7EE)),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
