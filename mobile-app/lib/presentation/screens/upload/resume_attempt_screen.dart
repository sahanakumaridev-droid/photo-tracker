import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/file_number.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import 'attempt_details_screen.dart';
import 'attempt_draft_controller.dart';
import 'attempt_location_screen.dart';
import 'attempt_photos_screen.dart';
import 'attempts_dashboard_screen.dart';

/// The "Resume Attempt" hub — a checklist screen. Company/Profile/Priority/
/// File Number are inline editable rows (no partial-attempt record exists
/// server-side until the first photo uploads, so these can't live on their
/// own screen). Photos/GPS/Serve To/Delivery Style/Pay Rate/Notes/Attempt
/// Status are tappable rows behind a progress bar; each pushes a dedicated
/// sub-screen sharing the same [AttemptDraftController] and pops back here.
///
/// Renders at the `/upload` route, replacing the old single-form
/// `UploadScreenV2`.
class ResumeAttemptScreen extends ConsumerStatefulWidget {
  const ResumeAttemptScreen({
    super.key,
    this.initialProfileId,
    this.resumeAttempt,
    this.localSnapshot,
  });

  /// "Add to Existing Profile" — pre-selects that profile and locks
  /// profile/company fields so only attempt-specific data is editable.
  final int? initialProfileId;

  /// A real, already-saved server Attempt to load for editing (Attempts
  /// Dashboard → Resume). When set, `initState` loads it via
  /// [AttemptDraftController.loadExistingAttempt] instead of running the
  /// local draft/snapshot restore flow.
  final Attempt? resumeAttempt;

  /// A locally-cached snapshot to resume (Attempts Dashboard → "Quick
  /// Saved" → tap a card). When set, `initState` loads it via
  /// [AttemptDraftController.resumeFromLocalSnapshot] — frozen
  /// location/timestamp, no fresh GPS fetch, same as the poor-network
  /// review flow.
  final Map<String, dynamic>? localSnapshot;

  @override
  ConsumerState<ResumeAttemptScreen> createState() =>
      _ResumeAttemptScreenState();
}

class _ResumeAttemptScreenState extends ConsumerState<ResumeAttemptScreen> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFF0F1219);
  static const Color _surface = Color(0xFF1C222E);
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _inkMuted = Color(0xFF94A3B8);
  static const Color _inkSubtle = Color(0xFF6B7A8D);
  static const Color _separator = Color(0xFF2A3340);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFEF4444);

  late final AttemptDraftController controller;

  @override
  void initState() {
    super.initState();
    controller = AttemptDraftController(initialProfileId: widget.initialProfileId);
    // The hub is the only screen guaranteed to stay mounted for the whole
    // session (sub-screens are pushed/popped on top of it), so it's the
    // one that reacts to the poor→good network transition with its own
    // (always-valid) context — the controller itself never stores one.
    controller.onNetworkImproved = () {
      if (!mounted) return;
      unawaited(controller.offerCachedAttemptReview(context, ref));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  /// Loading a real server Attempt (Attempts Dashboard → Resume) skips the
  /// local draft/snapshot restore flow entirely — explicitly opening a saved
  /// record shouldn't also prompt "resume your local draft?". GPS still
  /// always re-captures fresh afterward, same as the plain-init path.
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
      // Frozen location/timestamp by design — do not re-fetch fresh GPS,
      // same contract as the poor-network "Review & Save" flow.
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
    final profilesAsync = ref.watch(profilesProvider);
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (controller.poorNetwork ||
                          controller.locationFrozenFromCache) ...[
                        _buildNetworkCacheBanner(),
                        const SizedBox(height: 14),
                      ],
                      if (controller.isExistingProfileAttempt) ...[
                        _buildExistingProfileBanner(),
                        const SizedBox(height: 14),
                      ],
                      _buildCompanyRow(),
                      const SizedBox(height: 12),
                      _buildProfileRow(profilesAsync),
                      const SizedBox(height: 12),
                      _buildPriorityRow(),
                      const SizedBox(height: 12),
                      _buildFileNumberRow(),
                      const SizedBox(height: 20),
                      _buildProgressBar(),
                      const SizedBox(height: 14),
                      _buildChecklist(),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
        decoration: BoxDecoration(
          color: _surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 16, 14),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: _inkMuted,
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else if (controller.isExistingProfileAttempt) {
                  context.go('/profile/${controller.initialProfileId}');
                } else {
                  context.go('/home');
                }
              },
            ),
            Expanded(
              child: Text(
                controller.isExistingProfileAttempt
                    ? 'Add to Existing Profile'
                    : 'Resume Attempt',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Banners (reused as-is from the old form) ───────────────────────────────
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
        color: const Color(0xFFFEF3C7),
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
            color: const Color(0xFFB45309),
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
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF92400E),
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
                          title: const Text('Refresh location?'),
                          content: const Text(
                            'This replaces the cached location/time with a new GPS fix. '
                            'Only do this if the cached geotag is wrong.',
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
                      foregroundColor: const Color(0xFFB45309),
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

  Widget _buildExistingProfileBanner() {
    final name = controller.selectedProfile?.name;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.playlist_add_check_rounded,
              color: _accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null
                      ? 'Adding a new attempt'
                      : 'Adding a new attempt for $name',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Profile details stay as-is. Fill in only the attempt fields below.',
                  style: TextStyle(
                      fontSize: 12.5, color: _inkMuted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Inline rows: Company / Profile / Priority / File Number ────────────────
  Widget _rowCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );

  Widget _rowLabel(String label, IconData icon) => Row(
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
        ],
      );

  Widget _buildCompanyRow() => _rowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rowLabel('Company', Icons.business_rounded),
            const SizedBox(height: 10),
            if (controller.isExistingProfileAttempt)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _separator),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        companyOrDefault(controller.companyId).name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: _inkSubtle),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(controller.companyId),
                    initialValue: controller.companyId,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                    icon: const Icon(Icons.expand_more_rounded,
                        color: _inkSubtle),
                    items: [
                      for (final c in kCompanies)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      HapticFeedback.selectionClick();
                      controller.setCompany(v);
                    },
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _buildProfileRow(AsyncValue<List<ProfileModel>> profilesAsync) =>
      _rowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rowLabel('Profile', Icons.person_rounded),
            const SizedBox(height: 10),
            if (controller.isExistingProfileAttempt)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent, width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.selectedProfile?.name ??
                            'Loading profile…',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: _accent),
                  ],
                ),
              )
            else
              profilesAsync.when(
                loading: () => _shimmerBox(height: 52, radius: 12),
                error: (e, _) => _errorBox('Failed to load profiles'),
                data: (profiles) {
                  if (profiles.isEmpty) {
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showCreateProfileDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    );
                  }
                  return GestureDetector(
                    onTap: () => _showProfilePicker(profiles),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: controller.selectedProfile != null
                            ? _accentSoft
                            : _canvas,
                        borderRadius: BorderRadius.circular(12),
                        border: controller.selectedProfile != null
                            ? Border.all(color: _accent, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              controller.selectedProfile?.name ??
                                  'Select a profile',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: controller.selectedProfile != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: controller.selectedProfile != null
                                    ? _accent
                                    : _inkSubtle,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: controller.selectedProfile != null
                                ? _accent
                                : _inkSubtle,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );

  Widget _buildPriorityRow() => _rowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rowLabel('Priority Level', Icons.label_rounded),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  priorityCategoriesForCompany(controller.companyId).map((c) {
                final selected = controller.selectedCategory == c.value;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.setSelectedCategory(c.value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? c.color : c.softColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            selected ? c.color : c.color.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon,
                            size: 15, color: selected ? Colors.white : c.color),
                        const SizedBox(width: 6),
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : c.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _buildFileNumberRow() {
    final isNa = controller.fileNumberController.text.trim().toUpperCase() ==
        kFileNumberNA;
    return _rowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _rowLabel('File Number', Icons.tag_rounded),
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller.fileNumberController,
            style: const TextStyle(fontSize: 14, color: _ink),
            decoration: InputDecoration(
              hintText: 'e.g. 24-00123',
              hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.tag_rounded, size: 18, color: _inkSubtle),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              filled: true,
              fillColor: _canvas,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 0, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                if (isNa) {
                  controller.fileNumberController.clear();
                } else {
                  controller.fileNumberController.text = kFileNumberNA;
                  controller.fileNumberController.selection =
                      TextSelection.collapsed(offset: kFileNumberNA.length);
                }
                controller.notifyListeners();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isNa ? _accentSoft : _canvas,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isNa ? _accent : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  kFileNumberNA,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isNa ? _accent : _inkMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Required. Choose N/A when there is no dispatcher file number — '
            'watermarks will show the profile name instead.',
            style: TextStyle(fontSize: 11.5, color: _inkSubtle, height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── Progress bar + checklist ────────────────────────────────────────────
  bool get _servedToDone =>
      !controller.isSuccessfulAttempt ||
      controller.servedToController.text.trim().isNotEmpty;

  int get _doneCount {
    var n = 0;
    if (controller.selectedProfile != null) n++; // Profile
    n++; // Company — always has a default
    if (controller.hasPhoto) n++; // Photos
    if (controller.latitude != null && !controller.isLoadingLocation) n++;
    if (_servedToDone) n++; // Serve To
    if (controller.deliveryStyle != null) n++; // Delivery Style
    if (controller.payRateController.text.trim().isNotEmpty) n++; // Pay Rate
    if (controller.noteController.text.trim().isNotEmpty) n++; // Notes
    n++; // Attempt Status — always has a default
    return n;
  }

  static const int _kTotalChecklistItems = 9;

  Widget _buildProgressBar() {
    final fraction = _doneCount / _kTotalChecklistItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Attempt progress',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _inkMuted,
              ),
            ),
            const Spacer(),
            Text(
              '$_doneCount / $_kTotalChecklistItems',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: _separator,
            valueColor: const AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklist() {
    final servedToCaption = !controller.isSuccessfulAttempt
        ? 'Not required for this outcome'
        : controller.servedToController.text.trim().isEmpty
            ? 'Not set'
            : controller.servedToController.text.trim();
    final statusOpt = attemptStatusByValue(controller.attemptStatus) ??
        kAttemptStatuses.first;

    return Column(
      children: [
        _checklistRow(
          icon: Icons.camera_alt_rounded,
          label: 'Photos',
          done: controller.hasPhoto,
          caption: controller.selectedImages.isNotEmpty
              ? '${controller.selectedImages.length} photo'
                  '${controller.selectedImages.length > 1 ? 's' : ''} added'
              : controller.existingPhotoCount > 0
                  ? '${controller.existingPhotoCount} photo'
                      '${controller.existingPhotoCount > 1 ? 's' : ''} already on this attempt'
                  : 'Add at least one photo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AttemptPhotosScreen(controller: controller),
            ),
          ),
        ),
        _checklistRow(
          icon: Icons.location_on_rounded,
          label: 'GPS / Location',
          done: controller.latitude != null && !controller.isLoadingLocation,
          caption: controller.isLoadingLocation
              ? 'Locating…'
              : controller.locationError
                  ? 'Location error — tap to retry'
                  : controller.latitude == null
                      ? 'Not captured yet'
                      : (controller.addressController.text.trim().isNotEmpty
                          ? controller.addressController.text.trim()
                          : '${controller.latitude!.toStringAsFixed(5)}, '
                              '${controller.longitude!.toStringAsFixed(5)}'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AttemptLocationScreen(controller: controller),
            ),
          ),
        ),
        _checklistRow(
          icon: Icons.person_outline_rounded,
          label: 'Serve To',
          done: _servedToDone,
          caption: servedToCaption,
          onTap: _pushDetails,
        ),
        _checklistRow(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Delivery Style',
          done: controller.deliveryStyle != null,
          caption: controller.deliveryStyle ?? 'Not set',
          onTap: _pushDetails,
        ),
        _checklistRow(
          icon: Icons.attach_money_rounded,
          label: 'Pay Rate',
          done: controller.payRateController.text.trim().isNotEmpty,
          caption: controller.payRateController.text.trim().isEmpty
              ? 'Optional — not set'
              : '\$${controller.payRateController.text.trim()}',
          onTap: _pushDetails,
        ),
        _checklistRow(
          icon: Icons.edit_outlined,
          label: 'Notes',
          done: controller.noteController.text.trim().isNotEmpty,
          caption: controller.noteController.text.trim().isEmpty
              ? 'Optional — not set'
              : controller.noteController.text.trim(),
          onTap: _pushDetails,
        ),
        _checklistRow(
          icon: Icons.flag_rounded,
          label: 'Attempt Status',
          done: true,
          caption: statusOpt.label,
          onTap: _pushDetails,
          isLast: true,
        ),
      ],
    );
  }

  void _pushDetails() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttemptDetailsScreen(controller: controller),
        ),
      );

  Widget _checklistRow({
    required IconData icon,
    required String label,
    required bool done,
    required String caption,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: done
                    ? _successGreen.withValues(alpha: 0.12)
                    : _accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                done ? Icons.check_rounded : icon,
                size: 17,
                color: done ? _successGreen : _accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: done ? _inkMuted : _inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: _inkSubtle),
          ],
        ),
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────
  Widget _buildFooter() => Container(
        decoration: BoxDecoration(
          color: _surface,
          border: const Border(top: BorderSide(color: _separator, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: controller.canQuickSave
                      ? () async {
                          final saved =
                              await controller.quickSaveAttempt(context);
                          if (!saved || !context.mounted) return;
                          // Invalidate here, not just on the dashboard's
                          // post-pop — this screen can also exit via
                          // `context.go` (no pop), which skips that path.
                          ref.invalidate(localSnapshotsProvider);
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else if (controller.isExistingProfileAttempt) {
                            context.go(
                                '/profile/${controller.initialProfileId}');
                          } else {
                            context.go('/home');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.sd_storage_outlined, size: 18),
                  label: const Text('Pending Attempt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    disabledForegroundColor: _inkSubtle,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    side: BorderSide(
                        color: _accent.withValues(alpha: 0.45), width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final saved = await controller.quickSaveAttempt(context);
                    if (!saved || !context.mounted) return;
                    ref.invalidate(localSnapshotsProvider);
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else if (controller.isExistingProfileAttempt) {
                      context.go('/profile/${controller.initialProfileId}');
                    } else {
                      context.go('/home');
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Save & Exit',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  // ── Profile picker (identical picker logic to the old form) ───────────────
  void _showProfilePicker(List<ProfileModel> profiles) {
    HapticFeedback.lightImpact();
    final searchCtrl = TextEditingController();
    final nearbyIds = controller.nearbyProfileIds(ref);
    // Strictly enforce the proximity filter: only profiles with a photo
    // within kProfileProximityFt of this upload's location are selectable
    // here. No fallback to the full roster — if nothing is nearby, the
    // empty state below prompts creating a new profile at this location.
    final nearbyProfiles =
        profiles.where((p) => nearbyIds.contains(p.id)).toList();

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
          final filtered = nearby;

          void select(ProfileModel p) {
            HapticFeedback.selectionClick();
            controller.setSelectedProfile(p, ref: ref);
            Navigator.pop(sheetCtx);
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Select Profile',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${nearbyProfiles.length} within '
                        '${AttemptDraftController.kProfileProximityFt.toInt()} ft',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _inkSubtle,
                        ),
                      ),
                    ],
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
                      _showCreateProfileDialog();
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
                          Text('New Profile',
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
                      if (nearby.isNotEmpty) ...[
                        _pickerSectionLabel(
                            'Nearby · within '
                            '${AttemptDraftController.kProfileProximityFt.toInt()} ft'),
                        ...nearby.map((p) => _profilePickerTile(
                              p,
                              nearby: true,
                              onSelect: () => select(p),
                            )),
                      ],
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            searchCtrl.text.trim().isEmpty
                                ? 'No profiles within '
                                    '${AttemptDraftController.kProfileProximityFt.toInt()} ft of '
                                    'this location. Create one above.'
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

  Widget _pickerSectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: _inkSubtle,
          ),
        ),
      );

  Widget _profilePickerTile(
    ProfileModel p, {
    required bool nearby,
    required VoidCallback onSelect,
  }) {
    final sel = controller.selectedProfile?.id == p.id;
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: sel ? _accentSoft : _canvas,
          borderRadius: BorderRadius.circular(14),
          border: sel ? Border.all(color: _accent, width: 1.5) : null,
        ),
        child: Row(
          children: [
            if (nearby) ...[
              const Icon(Icons.location_on_rounded,
                  size: 15, color: _accent),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(p.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? _accent : _ink,
                  )),
            ),
            if (sel)
              const Icon(Icons.check_circle_rounded,
                  color: _accent, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Profile creation — full screen (Profile Location + Awaiting Attempt) ──
  Future<void> _showCreateProfileDialog() async {
    final created =
        await context.push<ProfileModel>('/profiles-management');
    if (created != null && mounted) {
      controller.setSelectedProfile(created);
      controller.showSnack(context, 'Profile "${created.name}" created');
    }
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
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

  Widget _shimmerBox({required double height, double radius = 8}) =>
      Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
