import 'package:flutter/material.dart';

import '../../data/models/company.dart';
import '../../data/models/profile_model.dart';

/// Profile job lifecycle (one-way):
/// pending → in_progress → completed → archived.
const String kProfilePending = 'pending';
const String kProfileInProgress = 'in_progress';
const String kProfileCompleted = 'completed';
const String kProfileArchived = 'archived';

const _rank = {
  kProfilePending: 0,
  kProfileInProgress: 1,
  kProfileCompleted: 2,
  kProfileArchived: 3,
};

String normalizeProfileStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty || s == 'awaiting_attempt' || s == 'open') {
    return kProfilePending;
  }
  if (s == 'in-progress') return kProfileInProgress;
  if (_rank.containsKey(s)) return s;
  return kProfilePending;
}

String profileStatusLabel(String? raw) {
  switch (normalizeProfileStatus(raw)) {
    case kProfileInProgress:
      return 'In Progress';
    case kProfileCompleted:
      return 'Completed';
    case kProfileArchived:
      return 'Archived';
    default:
      return 'Pending';
  }
}

Color profileStatusColor(String? raw) {
  switch (normalizeProfileStatus(raw)) {
    case kProfileInProgress:
      return const Color(0xFFD97706);
    case kProfileCompleted:
      return const Color(0xFF10B981);
    case kProfileArchived:
      return const Color(0xFF5C6778);
    default:
      return const Color(0xFF4A90E2);
  }
}

bool profileCanAddAttempts(String? raw) {
  final s = normalizeProfileStatus(raw);
  return s == kProfilePending || s == kProfileInProgress;
}

bool profileCanArchive(String? raw) =>
    normalizeProfileStatus(raw) == kProfileCompleted;

int attemptCapForProfile(ProfileModel? profile) {
  if (profile == null) {
    return companyOrDefault(null).attemptsForDiligence;
  }
  return companyOrDefault(profile.company).attemptsForDiligence;
}
