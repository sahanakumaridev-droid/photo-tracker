import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/profile_lifecycle.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import 'attempt_draft_controller.dart';

/// Unique attempts represented by a photo list (grouped by [PhotoModel.attemptId]).
int attemptCountFromPhotos(Iterable<PhotoModel> photos) {
  final ids = <int>{};
  var ungrouped = 0;
  for (final p in photos) {
    final id = p.attemptId;
    if (id != null && id != 0) {
      ids.add(id);
    } else {
      ungrouped++;
    }
  }
  return ids.length + ungrouped;
}

int jobAttemptCount({
  required List<PhotoModel> photos,
  int? profileAttemptsCount,
}) {
  final fromPhotos = attemptCountFromPhotos(photos);
  final fromProfile = profileAttemptsCount ?? 0;
  return fromProfile > fromPhotos ? fromProfile : fromPhotos;
}

ProfileModel? _profileById(WidgetRef ref, int profileId) {
  final list = ref.read(profilesProvider).valueOrNull;
  if (list == null) return null;
  for (final p in list) {
    if (p.id == profileId) return p;
  }
  return null;
}

/// Blocks a brand-new attempt when the profile is completed/archived or
/// already at the company's diligence cap.
Future<bool> ensureCanStartNewAttempt(
  BuildContext context,
  WidgetRef ref, {
  int? profileId,
  int? knownCount,
}) async {
  if (profileId == null) return true;
  final profile = _profileById(ref, profileId);
  if (profile != null && !profile.canAddAttempts) {
    if (context.mounted) {
      await showCompletedProfileDialog(context, profile.status);
    }
    return false;
  }
  var count = knownCount ?? 0;
  final cap = attemptCapForProfile(profile);
  // Don't stall the map/list buttons on a hanging attempts fetch when we
  // already know this job is under the cap.
  if (knownCount != null && knownCount < cap) {
    return true;
  }
  try {
    final attempts = await ref
        .read(profileAttemptsProvider(profileId).future)
        .timeout(const Duration(seconds: 2));
    count = attempts.length;
  } catch (_) {/* fall back to knownCount */}
  if (count >= cap) {
    if (context.mounted) await showMaxAttemptsDialog(context, cap: cap);
    return false;
  }
  return true;
}

Future<void> showCompletedProfileDialog(
  BuildContext context,
  String? status,
) {
  final archived = normalizeProfileStatus(status) == kProfileArchived;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        archived ? 'Profile archived' : 'Profile completed',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A2130),
        ),
      ),
      content: Text(
        archived
            ? 'Archived profiles are closed. You can still export records.'
            : 'This profile has a successful attempt or has met diligence. '
                'New attempts cannot be added. Archive it after payment is verified.',
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF5C6778),
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'OK',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A90E2),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> showMaxAttemptsDialog(BuildContext context, {int? cap}) {
  final n = cap ?? AttemptDraftController.kMaxAttemptsPerJob;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Maximum attempts reached',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A2130),
        ),
      ),
      content: Text(
        'This job already has $n attempts — the diligence maximum for this company.',
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF5C6778),
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'OK',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A90E2),
            ),
          ),
        ),
      ],
    ),
  );
}
