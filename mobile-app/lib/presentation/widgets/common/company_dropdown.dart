import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/company.dart';

/// Company menu that binds to the live [value] (id slug), not FormField
/// `initialValue` — that API kept showing First Legal after other picks.
class CompanyDropdown extends StatelessWidget {
  const CompanyDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.fillColor = const Color(0xFFF2F4F7),
    this.textStyle = const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1A2130),
    ),
  });

  final String value;
  final ValueChanged<String> onChanged;
  final Color fillColor;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final selected = companyOrDefault(value).id;
    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey(selected),
          value: selected,
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF8B95A5)),
          style: textStyle,
          items: [
            for (final c in kCompanies)
              DropdownMenuItem<String>(
                value: c.id,
                child: Text(
                  c.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selectedItemBuilder: (context) => [
            for (final c in kCompanies)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  c.name,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ),
    );
  }
}
