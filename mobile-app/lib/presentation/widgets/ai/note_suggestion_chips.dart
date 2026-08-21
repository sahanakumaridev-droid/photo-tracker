import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One-tap field notes so servers don't have to type common outcomes.
class NoteSuggestionChips extends StatelessWidget {
  const NoteSuggestionChips({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;

  static const chips = [
    'No answer',
    'Left card',
    'Posted on door',
    'Vacant',
    'Refused',
    'Business closed',
    'Neighbor said they moved',
    'Lights on, no response',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final cur = controller.text.trim();
              final next = cur.isEmpty ? chip : '$cur. $chip';
              controller.text = next;
              controller.selection =
                  TextSelection.collapsed(offset: next.length);
              onChanged?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE3E7EE)),
              ),
              child: Text(
                chip,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2130),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
