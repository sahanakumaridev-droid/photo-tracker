import 'package:flutter/material.dart';

import '../../../core/utils/category.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';

/// Labeled standing fields for a profile (name, company, priority,
/// delivery style, payout). Used on profile preview and locked on Add Attempt.
class ProfileFactsCard extends StatelessWidget {
  const ProfileFactsCard({
    required this.profile,
    this.locked = false,
    super.key,
  });

  final ProfileModel profile;
  final bool locked;

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _border = Color(0xFFE3E7EE);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);

  @override
  Widget build(BuildContext context) {
    final company = companyOrDefault(profile.company);
    final payout = profile.payRate != null ? '\$${profile.payRate}' : '—';
    final delivery = (profile.deliveryStyle ?? '').trim();
    final rows = <(String, String)>[
      ('Profile Name', profile.name),
      ('Company', company.name),
      ('Priority Level', categoryLabel(profile.serviceType)),
      ('Delivery Style', delivery.isEmpty ? '—' : delivery),
      ('Payout', payout),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: locked ? _accentSoft : _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: locked ? _accent : _border,
          width: locked ? 1.5 : 1,
        ),
        boxShadow: locked
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Profile details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _inkMuted,
                  ),
                ),
              ),
              if (locked) ...[
                const Icon(Icons.lock_outline_rounded,
                    size: 14, color: _accent),
                const SizedBox(width: 4),
                const Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _FactRow(label: rows[i].$1, value: rows[i].$2),
          ],
          const SizedBox(height: 10),
          Text(
            '${company.attemptsForDiligence} diligence attempts · '
            '${company.payoutScheduleDescription}',
            style: const TextStyle(
              fontSize: 12,
              color: _inkSubtle,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8B95A5),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2130),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
