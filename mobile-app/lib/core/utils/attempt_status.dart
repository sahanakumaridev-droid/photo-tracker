import 'package:flutter/cupertino.dart';

/// Attempt outcome — distinct from job lifecycle (`Photo.status`).
class AttemptStatusOption {
  const AttemptStatusOption({
    required this.value,
    required this.label,
    required this.color,
    required this.softColor,
    required this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final Color softColor;
  final IconData icon;
}

const String kAttemptStatusPending = 'pending';
const String kAttemptStatusSuccessful = 'successful';
const String kAttemptStatusUnsuccessful = 'unsuccessful';
const String kDefaultAttemptStatus = kAttemptStatusPending;

const List<AttemptStatusOption> kAttemptStatuses = <AttemptStatusOption>[
  AttemptStatusOption(
    value: kAttemptStatusPending,
    label: 'Pending',
    color: Color(0xFFB45309),
    softColor: Color(0x26B45309),
    icon: CupertinoIcons.clock_fill,
  ),
  AttemptStatusOption(
    value: kAttemptStatusSuccessful,
    label: 'Successful',
    color: Color(0xFF059669),
    softColor: Color(0x26059669),
    icon: CupertinoIcons.checkmark_seal_fill,
  ),
  AttemptStatusOption(
    value: kAttemptStatusUnsuccessful,
    label: 'Unsuccessful',
    color: Color(0xFFDC2626),
    softColor: Color(0x26DC2626),
    icon: CupertinoIcons.xmark_circle_fill,
  ),
];

AttemptStatusOption? attemptStatusByValue(String? value) {
  final v = (value ?? kDefaultAttemptStatus).toLowerCase();
  for (final s in kAttemptStatuses) {
    if (s.value == v) return s;
  }
  return null;
}

String normalizeAttemptStatus(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  if (v == kAttemptStatusSuccessful ||
      v == kAttemptStatusUnsuccessful ||
      v == kAttemptStatusPending) {
    return v;
  }
  return kDefaultAttemptStatus;
}

/// Map legacy `successful` bool → attempt status when status is absent.
String attemptStatusFromLegacy({String? attemptStatus, bool? successful}) {
  final raw = (attemptStatus ?? '').trim().toLowerCase();
  if (raw == kAttemptStatusSuccessful ||
      raw == kAttemptStatusUnsuccessful ||
      raw == kAttemptStatusPending) {
    return raw;
  }
  if (successful == null) return kDefaultAttemptStatus;
  return successful ? kAttemptStatusSuccessful : kAttemptStatusUnsuccessful;
}

bool isSuccessfulAttemptStatus(String? value) =>
    normalizeAttemptStatus(value) == kAttemptStatusSuccessful;
