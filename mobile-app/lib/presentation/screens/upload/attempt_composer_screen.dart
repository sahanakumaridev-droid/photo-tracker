import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/storage/local_storage.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/note_suggestion_chips.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../../widgets/common/company_dropdown.dart';
import '../../widgets/common/create_profile_dialog.dart';
import '../../widgets/common/pill_chip.dart';
import '../../widgets/common/profile_facts_card.dart';
import 'attempt_draft_controller.dart';
import 'attempt_limits.dart';
import 'attempts_dashboard_screen.dart';

/// Single-screen New / Edit Attempt. Photo + geotag first; every other field
/// is on this scroll. Pickers are sheets — never a sequential step screen.
class AttemptComposerScreen extends ConsumerStatefulWidget {
  const AttemptComposerScreen({
    super.key,
    required this.controller,
    required this.isEditing,
  });

  final AttemptDraftController controller;
  final bool isEditing;

  @override
  ConsumerState<AttemptComposerScreen> createState() =>
      _AttemptComposerScreenState();
}

class _AttemptComposerScreenState extends ConsumerState<AttemptComposerScreen> {
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _elevated = Color(0xFFEEF1F5);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _separator = Color(0xFFE3E7EE);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _accentMid = Color(0xFF64B5F6);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFEF4444);
  static const LinearGradient _btnGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF64B5F6), Color(0xFF4A90E2)],
  );

  AttemptDraftController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.uploadState == AttemptUploadState.success) {
              return Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildSuccessSummary()),
                  _buildSuccessFooter(),
                ],
              );
            }
            return Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPhotoHero(),
                        const SizedBox(height: 12),
                        if (controller.poorNetwork ||
                            controller.locationFrozenFromCache) ...[
                          _buildNetworkCacheBanner(),
                          const SizedBox(height: 14),
                        ],
                        _buildNotesCard(),
                        const SizedBox(height: 12),
                        if (controller.isSuccessfulAttempt) ...[
                          _buildServedToCard(context),
                          const SizedBox(height: 12),
                        ],
                        if (controller.latitude == null ||
                            controller.isLoadingLocation ||
                            controller.locationError) ...[
                          const SizedBox(height: 12),
                          _buildGeotagChip(),
                        ],
                        const SizedBox(height: 18),
                        if (controller.selectedProfile != null)
                          ProfileFactsCard(
                            profile: controller.selectedProfile!,
                            locked: true,
                            fileNumber: controller.fileNumberController.text
                                .trim(),
                          )
                        else
                          _buildJobCard(profilesAsync),
                        const SizedBox(height: 12),
                        _buildPayAndAddress(),
                        const SizedBox(height: 12),
                        _buildLinkProfilesCard(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _title {
    if (widget.isEditing) return 'Edit Attempt';
    return 'New Attempt';
  }

  Widget _buildHeader() {
    final profile = controller.selectedProfile;
    final attemptsAsync = profile == null
        ? null
        : ref.watch(profileAttemptsProvider(profile.id));
    final existing = attemptsAsync?.valueOrNull?.length ?? 0;
    final shown = widget.isEditing
        ? (existing == 0 ? 1 : existing)
        : existing + 1;
    final ofMax = profile?.attemptCap ?? AttemptDraftController.kMaxAttemptsPerJob;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            color: _inkMuted,
            onPressed: _leave,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.5,
                  ),
                ),
                if (profile != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (profile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent.withValues(alpha: 0.35)),
              ),
              child: Text(
                '$shown of $ofMax',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                  letterSpacing: -0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Photo (required, first) ─────────────────────────────────────────────
  Widget _buildPhotoHero() {
    final hasLocal = controller.selectedImages.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Photo',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: controller.hasPhoto
                    ? _successGreen.withValues(alpha: 0.16)
                    : const Color(0x26EF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                controller.hasPhoto ? 'Captured' : 'Required',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: controller.hasPhoto ? _successGreen : _errorRed,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Capture records GPS on the shutter.',
          style: TextStyle(fontSize: 13, color: _inkSubtle, height: 1.3),
        ),
        const SizedBox(height: 12),
        if (controller.existingPhotoCount > 0) ...[
          _existingPhotoBanner(),
          const SizedBox(height: 10),
        ],
        if (hasLocal)
          _photoStrip()
        else
          _emptyShutter(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Pressable(
                onTap: () =>
                    controller.pickImage(context, ImageSource.camera),
                child: _secondaryAction(
                  icon: Icons.photo_camera_rounded,
                  label: hasLocal ? 'Take another' : 'Take photo',
                  filled: !hasLocal,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Pressable(
                onTap: () =>
                    controller.pickImage(context, ImageSource.gallery),
                child: _secondaryAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Library',
                  filled: false,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyShutter() {
    return _Pressable(
      onTap: () => controller.pickImage(context, ImageSource.camera),
      child: Container(
        height: 132,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _accent.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_rounded, size: 40, color: _accent),
            SizedBox(height: 12),
            Text(
              'Tap to capture',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Geotag stamps automatically',
              style: TextStyle(fontSize: 13, color: _inkSubtle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoStrip() {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.selectedImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final file = controller.selectedImages[i];
          return _Pressable(
            onTap: () => _previewPhoto(i),
            child: SizedBox(
              width: 132,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 132,
                      height: 168,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(file, fit: BoxFit.cover, cacheWidth: 400),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: WatermarkBar(
                              takenAtIso: i < controller.takenAts.length
                                  ? controller.takenAts[i]
                                  : null,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.removeImage(i);
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _existingPhotoBanner() {
    final count = controller.existingPhotoCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_rounded, size: 18, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count photo${count > 1 ? 's' : ''} already on this attempt',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _previewPhoto(int i) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _canvas,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            controller.selectedImages[i],
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ── Geotag (recorded on capture, visible here — not a step) ─────────────
  Widget _buildGeotagChip() {
    final tagged = controller.latitude != null && !controller.isLoadingLocation;
    final waiting = controller.isLoadingLocation;
    final failed = controller.locationError;
    final acc = controller.gpsAccuracy;
    final coords = tagged
        ? '${controller.latitude!.toStringAsFixed(5)}, '
            '${controller.longitude!.toStringAsFixed(5)}'
        : null;
    final accLabel =
        acc != null && tagged ? ' · ±${acc.round()} m' : '';

    Color bg;
    Color fg;
    IconData icon;
    String label;
    if (tagged) {
      bg = _successGreen.withValues(alpha: 0.14);
      fg = _successGreen;
      icon = Icons.location_on_rounded;
      label = '${controller.addressController.text.trim().isNotEmpty ? controller.addressController.text.trim() : coords}$accLabel';
    } else if (waiting) {
      bg = _accentSoft;
      fg = _accent;
      icon = Icons.gps_fixed_rounded;
      label = 'Waiting for GPS…';
    } else if (failed) {
      bg = _errorRed.withValues(alpha: 0.12);
      fg = _errorRed;
      icon = Icons.location_off_rounded;
      label = controller.locationErrorMsg ?? 'Location unavailable';
    } else {
      bg = _elevated;
      fg = _inkSubtle;
      icon = Icons.location_searching_rounded;
      label = 'Tag records when you capture';
    }

    return _Pressable(
      onTap: failed ? () => controller.fetchLocation(context, ref) : () {},
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fg.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tagged ? 'Geotagged' : 'GPS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (failed)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: _inkSubtle),
                onPressed: () => controller.fetchLocation(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustLocation() async {
    HapticFeedback.lightImpact();
    controller.showSnack(
      context,
      'Attempt location is locked to your GPS geotag and cannot be changed.',
      isError: true,
    );
  }

  // ── Job identity (prefilled when opened from a job / existing profile) ──
  Widget _buildJobCard(AsyncValue<List<ProfileModel>> profilesAsync) {
    final locked = controller.isExistingProfileAttempt;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Job', Icons.badge_outlined),
          const SizedBox(height: 12),
          if (locked)
            _lockedRow(
              controller.selectedProfile?.name ?? 'Loading profile…',
              subtitle: companyOrDefault(controller.companyId).name,
            )
          else ...[
            _fieldCaption('Company'),
            const SizedBox(height: 6),
            CompanyDropdown(
              value: controller.companyId,
              onChanged: controller.setCompany,
            ),
            const SizedBox(height: 14),
            _fieldCaption('Profile'),
            const SizedBox(height: 6),
            profilesAsync.when(
              loading: () => _shimmer(height: 48),
              error: (_, __) => _errorBox('Failed to load profiles'),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return _Pressable(
                    onTap: _createProfile,
                    child: _secondaryAction(
                      icon: Icons.add_rounded,
                      label: 'Add Profile',
                      filled: true,
                    ),
                  );
                }
                return _Pressable(
                  onTap: () => _showProfilePicker(profiles),
                  child: _selectRow(
                    value: controller.selectedProfile?.name,
                    placeholder: 'Select a profile',
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServedToCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldCaption('Served to', optional: true),
          const SizedBox(height: 6),
          _Pressable(
            onTap: () => _showServedToPicker(context),
            child: _selectRow(
              value: controller.servedToController.text.trim().isEmpty
                  ? null
                  : controller.servedToController.text.trim(),
              placeholder: 'Who was served',
            ),
          ),
          if (controller.servedToController.text.trim().isNotEmpty &&
              AttemptDraftController.servedToNeedsRelation(
                  controller.servedToController.text)) ...[
            const SizedBox(height: 14),
            _fieldCaption('Relation to'),
            const SizedBox(height: 6),
            _inputField(
              controller: controller.relationToController,
              hint: 'e.g. Spouse, coworker',
              icon: Icons.groups_outlined,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcomeSegment() {
    final options = kAttemptStatuses
        .where((s) => s.value != kAttemptStatusPending)
        .toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final s in options)
            Expanded(
              child: _Pressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.setAttemptStatus(s.value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: controller.attemptStatus == s.value
                        ? _surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: controller.attemptStatus == s.value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: controller.attemptStatus == s.value
                          ? s.color
                          : _inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Outcome', Icons.flag_rounded),
          const SizedBox(height: 8),
          _outcomeSegment(),
          const SizedBox(height: 14),
          _sectionLabel('Notes', Icons.edit_outlined),
          const SizedBox(height: 8),
          _inputField(
            controller: controller.noteController,
            hint: 'Tap the mic and talk the note',
            icon: Icons.description_outlined,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [SentenceCaseInputFormatter()],
            voice: true,
            voiceMode: VoiceFillMode.append,
          ),
          const SizedBox(height: 10),
          NoteSuggestionChips(
            controller: controller.noteController,
            outcome: controller.attemptStatus,
            onChanged: controller.bump,
          ),
          if (controller.isSuccessfulAttempt) ...[
            const SizedBox(height: 10),
            SubjectDescriptionForm(
              description: controller.subjectDescription,
              onChanged: controller.bump,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayAndAddress() {
    return const SizedBox.shrink();
  }

  Widget _buildLinkProfilesCard() {
    if (controller.selectedProfile == null) return const SizedBox.shrink();
    final nearby = controller.nearbyLinkProfiles(ref);
    if (nearby.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Link profiles', Icons.link_rounded, optional: true),
          const SizedBox(height: 6),
          Text(
            'Duplicate this attempt onto nearby profiles after you save. '
            'Only shown when another profile is within '
            '${AttemptDraftController.kProfileProximityFt.toInt()} ft.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in nearby)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.toggleLinkProfile(p.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: controller.linkProfileIds.contains(p.id)
                          ? _accentSoft
                          : _canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: controller.linkProfileIds.contains(p.id)
                            ? _accent
                            : _separator,
                        width: controller.linkProfileIds.contains(p.id)
                            ? 1.5
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          controller.linkProfileIds.contains(p.id)
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 20,
                          color: controller.linkProfileIds.contains(p.id)
                              ? _accent
                              : _inkSubtle,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    final canUpload = controller.canUpload;
    final isInProgress = controller.uploadState ==
            AttemptUploadState.uploading ||
        controller.uploadState == AttemptUploadState.processing;
    final tappable =
        canUpload && controller.uploadState == AttemptUploadState.idle;

    String completeLabel;
    if (controller.uploadState == AttemptUploadState.uploading) {
      final total = controller.selectedImages.length;
      completeLabel = total > 1
          ? 'Uploading ${controller.uploadedCount + 1} of $total…'
          : 'Uploading photo…';
    } else if (controller.uploadState == AttemptUploadState.processing) {
      completeLabel = 'Processing…';
    } else if (canUpload) {
      completeLabel = widget.isEditing ? 'Save changes' : 'Complete Attempt';
    } else if (!controller.hasPhoto) {
      completeLabel = 'Take photo';
    } else {
      completeLabel = controller.missingFieldsHint();
    }
    final primaryReady = canUpload || isInProgress || !controller.hasPhoto;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(top: BorderSide(color: _separator, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInProgress) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                backgroundColor: _accent.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(_accentMid),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: isInProgress ? null : _saveAndExit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkMuted,
                      side: const BorderSide(color: _separator, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Save & exit',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: primaryReady ? _btnGradient : null,
                      color: primaryReady ? null : _elevated,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: tappable
                          ? [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.38),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: ElevatedButton(
                      onPressed: isInProgress
                          ? null
                          : () {
                              if (tappable) {
                                controller.upload(context, ref);
                              } else if (!controller.hasPhoto) {
                                controller.pickImage(
                                  context,
                                  ImageSource.camera,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor: _inkSubtle,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        completeLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primaryReady ? Colors.white : _inkSubtle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndExit() async {
    HapticFeedback.lightImpact();
    if (controller.canQuickSave) {
      final saved = await controller.quickSaveAttempt(context);
      if (!saved || !mounted) return;
    } else {
      controller.saveDraft();
    }
    ref.invalidate(localSnapshotsProvider);
    _leave();
  }

  void _leave() {
    refreshProfileWork(
      ref,
      profileId: controller.selectedProfile?.id ?? controller.initialProfileId,
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (controller.isExistingProfileAttempt) {
      context.go('/log');
    } else {
      context.go('/upload');
    }
  }

  Widget _buildSuccessSummary() {
    final n = controller.uploadedCount > 0
        ? controller.uploadedCount
        : controller.selectedImages.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: _successGreen, size: 40),
          ),
          const SizedBox(height: 20),
          const Text(
            'Attempt saved',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            n > 1
                ? '$n photos logged successfully'
                : 'Photo logged successfully',
            style: const TextStyle(fontSize: 14, color: _inkMuted),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _separator),
            ),
            child: Column(
              children: [
                _summaryRow(
                    'Profile', controller.selectedProfile?.name ?? '—'),
                const Divider(height: 20, color: _separator),
                _summaryRowWidget(
                    'Priority',
                    PriorityChip(category: controller.selectedCategory)),
                const Divider(height: 20, color: _separator),
                _summaryRowWidget(
                    'Status', StatusChip(status: controller.attemptStatus)),
                const Divider(height: 20, color: _separator),
                _summaryRow(
                  'File #',
                  (controller.selectedProfile?.fileNumber ?? '')
                          .trim()
                          .isEmpty
                      ? '—'
                      : controller.selectedProfile!.fileNumber!.trim(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _inkMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
          ),
        ),
      ],
    );
  }

  Widget _summaryRowWidget(String label, Widget value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _inkMuted)),
        const Spacer(),
        value,
      ],
    );
  }

  Widget _buildSuccessFooter() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _separator, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          if (controller.lastUploadedPhotoId != null)
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      context.push('/photo/${controller.lastUploadedPhotoId}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View post',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          if (controller.lastUploadedPhotoId != null) const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _leave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _successGreen,
                  side: BorderSide(
                      color: _successGreen.withValues(alpha: 0.4), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile picker ──────────────────────────────────────────────────────
  void _showProfilePicker(List<ProfileModel> profiles) {
    HapticFeedback.lightImpact();
    final searchCtrl = TextEditingController();
    final openProfiles = profiles.where((p) => p.canAddAttempts).toList();
    final nearbyIds = controller.nearbyProfileIds(ref);
    final nearbyProfiles =
        openProfiles.where((p) => nearbyIds.contains(p.id)).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final nearby = query.isEmpty
              ? nearbyProfiles
              : nearbyProfiles
                  .where((p) => p.name.toLowerCase().contains(query))
                  .toList();

          Future<void> select(ProfileModel p) async {
            if (!widget.isEditing) {
              final ok = await ensureCanStartNewAttempt(
                context,
                ref,
                profileId: p.id,
                knownCount: p.attemptsCount,
              );
              if (!ok || !mounted) return;
            }
            HapticFeedback.selectionClick();
            controller.setSelectedProfile(p, ref: ref);
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _separator,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select profile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Search profiles…',
                      hintStyle: const TextStyle(color: _inkSubtle),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: _inkSubtle),
                      filled: true,
                      fillColor: _canvas,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _createProfile();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded,
                              size: 18, color: _accent),
                          SizedBox(width: 10),
                          Text('New profile',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _accent)),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (nearby.isNotEmpty)
                        ...nearby.map((p) {
                          final sel = controller.selectedProfile?.id == p.id;
                          return GestureDetector(
                            onTap: () => select(p),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              decoration: BoxDecoration(
                                color: sel ? _accentSoft : _canvas,
                                borderRadius: BorderRadius.circular(14),
                                border: sel
                                    ? Border.all(color: _accent, width: 1.5)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      size: 15, color: _accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: sel
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: sel ? _accent : _ink,
                                      ),
                                    ),
                                  ),
                                  if (sel)
                                    const Icon(Icons.check_circle_rounded,
                                        color: _accent, size: 20),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (nearby.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            searchCtrl.text.trim().isEmpty
                                ? 'No profiles within '
                                    '${AttemptDraftController.kProfileFilterFt.toInt()} ft. '
                                    'Create one above.'
                                : 'No nearby profiles match '
                                    '"${searchCtrl.text.trim()}"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _inkSubtle, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _createProfile() async {
    final created = await showCreateProfileDialog(context);
    if (created != null && mounted) {
      controller.setSelectedProfile(created, ref: ref);
      controller.showSnack(context, 'Profile "${created.name}" created');
    }
  }

  void _showServedToPicker(BuildContext context) {
    HapticFeedback.lightImpact();

    void select(String value) {
      HapticFeedback.selectionClick();
      controller.setServedTo(value);
      Navigator.pop(context);
    }

    final servedToOptions = controller.servedToChoices(ref);

    Future<void> createCustom() async {
      final nameCtrl = TextEditingController();
      var gender = 'male';
      final result = await showDialog<({String name, String gender})>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (dialogCtx, setDialog) => AlertDialog(
            backgroundColor: _surface,
            title: const Text('New name',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseInputFormatter()],
                  style: const TextStyle(color: _ink),
                  decoration: const InputDecoration(hintText: 'Full name'),
                ),
                const SizedBox(height: 14),
                const Text('Gender',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _inkMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const [
                      ('male', 'Male'),
                      ('female', 'Female'),
                      ('other', 'Other'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: gender == option.$1,
                        onSelected: (_) =>
                            setDialog(() => gender = option.$1),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(dialogCtx, (name: name, gender: gender));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (result != null && result.name.isNotEmpty) {
        await controller.addCustomServedToName(
          result.name,
          gender: result.gender,
        );
        select(result.name);
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        var query = '';
        var filter = 'all';
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final genders = LocalStorage.getServedToGenders();
            String groupOf(String name) {
              const known = {
                'John Doe': 'male',
                'Jane Doe': 'female',
              };
              final savedGender = known[name] ?? genders[name];
              if (savedGender == 'male' || savedGender == 'female') {
                return savedGender!;
              }
              return 'saved';
            }

            bool matches(String name) {
              final q = query.trim().toLowerCase();
              if (q.isNotEmpty && !name.toLowerCase().contains(q)) {
                return false;
              }
              if (filter == 'all') return true;
              return groupOf(name) == filter;
            }

            final quick = [
              for (final name in const ['Same as Profile', 'Posted to Door'])
                if (filter == 'all' && matches(name)) name,
            ];
            final people = [
              for (final name in servedToOptions)
                if (name != 'Same as Profile' &&
                    name != 'Posted to Door' &&
                    matches(name))
                  name,
            ];
            final male = [
              for (final name in people)
                if (groupOf(name) == 'male') name,
            ];
            final female = [
              for (final name in people)
                if (groupOf(name) == 'female') name,
            ];
            final saved = [
              for (final name in people)
                if (groupOf(name) != 'male' && groupOf(name) != 'female') name,
            ];

            Widget section(String title, List<String> names) {
              if (names.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _inkMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final name in names)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(name,
                          style: const TextStyle(color: _ink, fontSize: 15)),
                      onTap: () => select(name),
                    ),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _separator,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Served to',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        onChanged: (v) => setSheet(() => query = v),
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Search names',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF2F4F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final option in const [
                            ('all', 'All'),
                            ('male', 'Male'),
                            ('female', 'Female'),
                            ('saved', 'Saved'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(option.$2),
                                selected: filter == option.$1,
                                onSelected: (_) =>
                                    setSheet(() => filter = option.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          if (query.trim().isEmpty && filter == 'all')
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading:
                                  const Icon(Icons.add_rounded, color: _accent),
                              title: const Text('New name',
                                  style: TextStyle(
                                      color: _accent,
                                      fontWeight: FontWeight.w600)),
                              onTap: createCustom,
                            ),
                          section('Quick', quick),
                          section('Male', male),
                          section('Female', female),
                          section('Saved names', saved),
                          if (quick.isEmpty && people.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No names match.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _inkSubtle, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNetworkCacheBanner() {
    final frozen = controller.locationFrozenFromCache;
    final title = frozen
        ? 'Location & time locked from cache'
        : 'Poor network — auto-caching attempt';
    final body = frozen
        ? 'Upload will use the cached geotag and capture time from when signal was bad — not your current GPS.'
        : 'Inputs are snapshotted every few seconds. Location/time will lock to the last known fix while signal stays poor.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x26F59E0B),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            frozen
                ? Icons.lock_clock
                : Icons.signal_cellular_connected_no_internet_4_bar,
            color: const Color(0xFFFBBF24),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFDE68A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFFDE68A),
                    height: 1.35,
                  ),
                ),
                if (frozen) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      final unlock = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: _surface,
                          title: const Text('Refresh location?',
                              style: TextStyle(color: _ink)),
                          content: const Text(
                            'This replaces the cached location/time with a new GPS fix. '
                            'Only do this if the cached geotag is wrong.',
                            style: TextStyle(color: _inkMuted),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Keep cached'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Refresh GPS'),
                            ),
                          ],
                        ),
                      );
                      if (unlock == true && mounted) {
                        controller.unlockLocationFromCache();
                        unawaited(controller.fetchLocation(context, ref));
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFBBF24),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Unlock & refresh GPS',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared atoms ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );

  Widget _sectionLabel(String label, IconData icon,
      {bool required = false, bool optional = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _inkMuted,
            letterSpacing: 0.1,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 6),
          const Text('*',
              style: TextStyle(
                  color: _errorRed, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
        if (optional)
          const Text(
            '  optional',
            style: TextStyle(fontSize: 11, color: _inkSubtle),
          ),
      ],
    );
  }

  Widget _fieldCaption(String label, {bool optional = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _inkSubtle,
          ),
        ),
        if (optional)
          const Text(
            '  optional',
            style: TextStyle(fontSize: 11, color: _inkSubtle),
          ),
      ],
    );
  }

  Widget _lockedRow(String title, {String? subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: _inkMuted)),
                ],
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded, size: 16, color: _accent),
        ],
      ),
    );
  }

  Widget _selectRow({String? value, required String placeholder}) {
    final has = value != null && value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: has ? _accentSoft : _canvas,
        borderRadius: BorderRadius.circular(12),
        border: has ? Border.all(color: _accent, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              has ? value : placeholder,
              style: TextStyle(
                fontSize: 14,
                fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                color: has ? _accent : _inkSubtle,
              ),
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: has ? _accent : _inkSubtle, size: 20),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required bool filled,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: filled ? _accent : _elevated,
        borderRadius: BorderRadius.circular(14),
        border: filled ? null : Border.all(color: _separator),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: filled ? Colors.white : _inkMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool voice = false,
    VoiceFillMode voiceMode = VoiceFillMode.replace,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 15, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: _inkSubtle),
        suffixIcon: voice
            ? VoiceMicButton(controller: controller, mode: voiceMode)
            : null,
        filled: true,
        fillColor: _canvas,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _errorRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: _errorRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(fontSize: 13, color: _errorRed)),
            ),
          ],
        ),
      );

  Widget _shimmer({required double height}) => Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
