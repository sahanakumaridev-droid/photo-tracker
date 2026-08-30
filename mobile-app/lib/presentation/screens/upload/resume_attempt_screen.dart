import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/attempt.dart';
import '../../../data/models/profile_model.dart';
import 'attempt_composer_screen.dart';
import 'attempt_draft_controller.dart';

/// Entry for `/upload`. Owns the [AttemptDraftController] lifecycle and
/// bootstraps draft / resume / existing-profile prefill, then shows the
/// single-screen [AttemptComposerScreen].
class ResumeAttemptScreen extends ConsumerStatefulWidget {
  const ResumeAttemptScreen({
    super.key,
    this.initialProfileId,
    this.initialProfile,
    this.resumeAttempt,
    this.localSnapshot,
  });

  /// "Add to Existing Profile" / Jobs New Attempt — pre-selects that profile
  /// and locks profile/company so attempt fields are editable in place.
  final int? initialProfileId;

  final ProfileModel? initialProfile;

  /// A real, already-saved server Attempt to load for editing.
  final Attempt? resumeAttempt;

  /// A locally-cached snapshot to resume (Quick Saved).
  final Map<String, dynamic>? localSnapshot;

  @override
  ConsumerState<ResumeAttemptScreen> createState() =>
      _ResumeAttemptScreenState();
}

class _ResumeAttemptScreenState extends ConsumerState<ResumeAttemptScreen> {
  late final AttemptDraftController controller;

  @override
  void initState() {
    super.initState();
    controller = AttemptDraftController(
      initialProfileId: widget.initialProfileId,
      seedProfile: widget.initialProfile,
    );
    controller.onNetworkImproved = () {
      if (!mounted) return;
      unawaited(controller.offerCachedAttemptReview(context, ref));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    final resumeAttempt = widget.resumeAttempt;
    if (resumeAttempt != null) {
      await controller.loadExistingAttempt(resumeAttempt, ref: ref);
      if (!mounted) return;
      unawaited(controller.fetchLocation(context, ref));
      controller.startPoorNetworkMonitoring();
      return;
    }
    final localSnapshot = widget.localSnapshot;
    if (localSnapshot != null) {
      await controller.resumeFromLocalSnapshot(localSnapshot, ref: ref);
      if (!mounted) return;
      controller.startPoorNetworkMonitoring();
      return;
    }
    await controller.init(context, ref);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AttemptComposerScreen(
      controller: controller,
      isEditing: widget.resumeAttempt != null || widget.localSnapshot != null,
    );
  }
}
