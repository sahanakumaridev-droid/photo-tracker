import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/photo_model.dart';
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

/// Blocks a brand-new attempt when this job already has five.
/// Resume / edit of an existing attempt should not call this.
Future<bool> ensureCanStartNewAttempt(
  BuildContext context,
  WidgetRef ref, {
  int? profileId,
  int? knownCount,
}) async {
  if (profileId == null) return true;
  var count = knownCount ?? 0;
  try {
    final attempts = await ref.read(profileAttemptsProvider(profileId).future);
    count = attempts.length;
  } catch (_) {/* fall back to knownCount */}
  if (count >= AttemptDraftController.kMaxAttemptsPerJob) {
    if (context.mounted) await showMaxAttemptsDialog(context);
    return false;
  }
  return true;
}

Future<void> showMaxAttemptsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Maximum attempts reached',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A2130),
        ),
      ),
      content: Text(
        'This job already has ${AttemptDraftController.kMaxAttemptsPerJob} '
        'attempts — the maximum allowed. Open the job to edit an existing attempt.',
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
