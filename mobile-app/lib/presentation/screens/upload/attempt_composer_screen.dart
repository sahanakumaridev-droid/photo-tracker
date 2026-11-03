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
part 'attempt_composer_cards.dart';
part 'attempt_composer_pickers.dart';

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

const Color _canvas = Color(0xFFF2F4F7);
const Color _surface = Color(0xFFFFFFFF);
const Color _elevated = Color(0xFFEEF1F5);
const Color _ink = Color(0xFF1A2130);
const Color _inkMuted = Color(0xFF5C6778);
const Color _inkSubtle = Color(0xFF8B95A5);
const Color _separator = Color(0xFFE3E7EE);
const Color _accent = Color(0xFF4A90E2);
const Color _accentSoft = Color(0x1F4A90E2);
const Color _accentMid = Color(0xFF64B5F6);
const Color _successGreen = Color(0xFF10B981);
const Color _errorRed = Color(0xFFEF4444);
const LinearGradient _btnGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF64B5F6), Color(0xFF4A90E2)],
);

class _AttemptComposerScreenState extends ConsumerState<AttemptComposerScreen> {
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
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});
}
