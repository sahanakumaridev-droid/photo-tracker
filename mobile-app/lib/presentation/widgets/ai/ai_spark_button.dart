import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/settings/ai_assistant_sheet.dart';

/// Sparkle control that opens GeoTag AI from Home / Earnings.
class AiSparkButton extends StatelessWidget {
  const AiSparkButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showAiAssistantSheet(context);
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A90E2), Color(0xFF1E88E5)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334A90E2),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded,
            color: Colors.white, size: 22),
      ),
    );
  }
}
