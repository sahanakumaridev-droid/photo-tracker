import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/text_formatters.dart';
import '../../widgets/common/pill_chip.dart';
import 'attempt_draft_controller.dart';

/// Dedicated Details screen, pushed from the Resume Attempt hub. Combines
/// the old form's Delivery Style + Pay Rate + Details (Note / Attempt
/// Status / Served To / Relation To) sections, rebound to the shared
/// [AttemptDraftController].
///
/// **Complete Attempt lives only here** — the footer's primary button calls
/// `controller.upload()`, the only place that logic runs in the new
/// architecture. When the upload succeeds, the body swaps for the old
/// form's success summary and the footer swaps for View Post / Done.
class AttemptDetailsScreen extends ConsumerWidget {
  const AttemptDetailsScreen({super.key, required this.controller});

  final AttemptDraftController controller;

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFF0F1219);
  static const Color _surface = Color(0xFF1C222E);
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _inkMuted = Color(0xFF94A3B8);
  static const Color _inkSubtle = Color(0xFF6B7A8D);
  static const Color _separator = Color(0xFF2A3340);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 22, color: _inkMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Attempt Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: controller.uploadState == AttemptUploadState.success
                    ? _buildSuccessSummary()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDeliveryStyleSection(),
                            const SizedBox(height: 14),
                            _buildPayRateSection(),
                            const SizedBox(height: 14),
                            _buildDetailsSection(context),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
              ),
              _buildFooter(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delivery Style ──────────────────────────────────────────────────────
  Widget _buildDeliveryStyleSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
                'Delivery Style', Icons.assignment_turned_in_outlined),
            const SizedBox(height: 6),
            const Text(
              'How this delivery was completed.',
              style: TextStyle(fontSize: 13, color: _inkSubtle),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: controller.deliveryStyle,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more_rounded,
                      color: _inkSubtle),
                  hint: const Row(
                    children: [
                      Icon(Icons.assignment_turned_in_outlined,
                          size: 18, color: _inkSubtle),
                      SizedBox(width: 8),
                      Text('Select a delivery style…',
                          style:
                              TextStyle(fontSize: 14, color: _inkSubtle)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, color: _ink),
                  borderRadius: BorderRadius.circular(12),
                  items: AttemptDraftController.kDeliveryStyles
                      .map((s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s,
                                style: const TextStyle(
                                    fontSize: 14, color: _ink)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    controller.setDeliveryStyle(value);
                  },
                ),
              ),
            ),
          ],
        ),
      );

  // ── Pay Rate ────────────────────────────────────────────────────────────
  Widget _buildPayRateSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Pay Rate', Icons.attach_money),
            const SizedBox(height: 12),
            _fieldLabel('Pay Rate (\$)', optional: true),
            const SizedBox(height: 6),
            _inputField(
              controller: controller.payRateController,
              hint: 'e.g. 30',
              icon: Icons.attach_money,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      );

  // ── Details: Note, Attempt Status, Served To / Relation To ────────────────
  Widget _buildDetailsSection(BuildContext context) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Note', Icons.edit_outlined),
            const SizedBox(height: 14),
            _inputField(
              controller: controller.noteController,
              hint: 'Add a note about this photo…',
              icon: Icons.description_outlined,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: const [SentenceCaseInputFormatter()],
            ),
            const SizedBox(height: 16),
            _sectionLabel(
              'Attempt Status',
              Icons.flag_rounded,
              done: true,
            ),
            const SizedBox(height: 6),
            const Text(
              'Outcome of this service attempt.',
              style: TextStyle(fontSize: 13, color: _inkSubtle),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              // "Pending" is the implicit default for an attempt whose
              // outcome isn't known yet — not something to hand-pick once
              // you're here recording what happened, so only offer a real
              // outcome to choose between.
              children: kAttemptStatuses
                  .where((s) => s.value != kAttemptStatusPending)
                  .map((s) {
                final selected = controller.attemptStatus == s.value;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.setAttemptStatus(s.value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? s.color : s.softColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? s.color
                            : s.color.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          s.icon,
                          size: 15,
                          color: selected ? Colors.white : s.color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : s.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (controller.isSuccessfulAttempt) ...[
              const SizedBox(height: 16),
              _fieldLabel('Served To', optional: true),
              const SizedBox(height: 6),
              _buildServedToField(context),
              if (controller.servedToController.text.trim().isNotEmpty &&
                  controller.servedToController.text.trim() !=
                      'Same as profile') ...[
                const SizedBox(height: 16),
                _fieldLabel('Relation To'),
                const SizedBox(height: 6),
                _inputField(
                  controller: controller.relationToController,
                  hint: 'e.g. Spouse, Coworker, Roommate',
                  icon: Icons.groups_outlined,
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ],
          ],
        ),
      );

  // ── Served To picker field ────────────────────────────────────────────────
  Widget _buildServedToField(BuildContext context) {
    final hasValue = controller.servedToController.text.trim().isNotEmpty;
    return GestureDetector(
      onTap: () => _showServedToPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hasValue ? _accentSoft : _canvas,
          borderRadius: BorderRadius.circular(12),
          border: hasValue ? Border.all(color: _accent, width: 1.5) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.person_outline,
                size: 18, color: hasValue ? _accent : _inkSubtle),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue
                    ? controller.servedToController.text
                    : 'Select who was served',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? _accent : _inkSubtle,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: hasValue ? _accent : _inkSubtle, size: 20),
          ],
        ),
      ),
    );
  }

  void _showServedToPicker(BuildContext context) {
    HapticFeedback.lightImpact();

    void select(String value) {
      HapticFeedback.selectionClick();
      controller.setServedTo(value);
      Navigator.pop(context);
    }

    Future<void> createCustom() async {
      final nameCtrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Served To'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            inputFormatters: const [TitleCaseInputFormatter()],
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, nameCtrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        await controller.addCustomServedToName(name);
        select(name);
      }
    }

    // Presets first, then remembered custom names (most-recent first),
    // skipping any that duplicate a preset.
    final servedToOptions = [
      ...AttemptDraftController.kServedToPresets,
      ...controller.customServedToNames.where(
          (n) => !AttemptDraftController.kServedToPresets.contains(n)),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
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
              child: Text(
                'Served To',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: servedToOptions
                    .map((p) => _servedToPickerTile(
                          label: p,
                          onSelect: () => select(p),
                        ))
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: GestureDetector(
                onTap: createCustom,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          size: 18, color: _accent),
                      SizedBox(width: 10),
                      Text('New name',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _accent)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _servedToPickerTile(
      {required String label, required VoidCallback onSelect}) {
    final selected = controller.servedToController.text.trim() == label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onSelect,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? _accentSoft : _canvas,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: _accent, width: 1.5) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? _accent : _ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: _accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Success summary — replaces the form once the attempt is created ────────
  Widget _buildSuccessSummary() {
    final n = controller.selectedImages.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _successGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: _successGreen, size: 48),
            ),
            const SizedBox(height: 20),
            const Text('Attempt Created',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
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
                      label: 'Profile',
                      value: controller.selectedProfile?.name ?? '—'),
                  const Divider(height: 20),
                  _summaryRow(
                      label: 'Priority',
                      valueWidget:
                          PriorityChip(category: controller.selectedCategory)),
                  const Divider(height: 20),
                  _summaryRow(
                      label: 'Status',
                      valueWidget:
                          StatusChip(status: controller.attemptStatus)),
                  const Divider(height: 20),
                  _summaryRow(
                    label: 'File #',
                    value: controller.fileNumberController.text.trim().isEmpty
                        ? '—'
                        : controller.fileNumberController.text.trim(),
                  ),
                  if (controller.addressController.text.trim().isNotEmpty) ...[
                    const Divider(height: 20),
                    _summaryRow(
                        label: 'Location',
                        value: controller.addressController.text.trim()),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
      {required String label, String? value, Widget? valueWidget}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _inkMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: valueWidget ??
                Text(
                  value!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ),
      ],
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────
  Widget _buildFooter(BuildContext context, WidgetRef ref) {
    if (controller.uploadState == AttemptUploadState.success) {
      return Container(
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
            if (controller.lastUploadedPhotoId != null)
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => context
                        .push('/photo/${controller.lastUploadedPhotoId}'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('View Post',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ),
            if (controller.lastUploadedPhotoId != null)
              const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => controller.isExistingProfileAttempt
                      ? context.go('/profile/${controller.initialProfileId}')
                      : context.go('/home'),
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const Text('Done',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _successGreen,
                    side: BorderSide(
                        color: _successGreen.withValues(alpha: 0.4),
                        width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final canUpload = controller.canUpload;
    final isInProgress = controller.uploadState ==
            AttemptUploadState.uploading ||
        controller.uploadState == AttemptUploadState.processing;
    final tappable = canUpload && controller.uploadState == AttemptUploadState.idle;

    String label;
    if (controller.uploadState == AttemptUploadState.uploading) {
      final total = controller.selectedImages.length;
      label = total > 1
          ? 'Uploading ${controller.uploadedCount + 1} of $total…'
          : 'Uploading photo…';
    } else if (controller.uploadState == AttemptUploadState.processing) {
      label = 'Processing…';
    } else {
      label = canUpload
          ? 'Complete Attempt'
          : controller.missingFieldsHint();
    }

    return Container(
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
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: controller.canQuickSave
                  ? () async {
                      final saved =
                          await controller.quickSaveAttempt(context);
                      if (saved &&
                          context.mounted &&
                          Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    }
                  : null,
              icon: const Icon(Icons.sd_storage_outlined, size: 18),
              label: const Text('Quick Save Attempt',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                disabledForegroundColor: _inkSubtle,
                side: BorderSide(
                    color: _accent.withValues(alpha: 0.45), width: 1.5),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: (canUpload || isInProgress) ? _btnGradient : null,
                color: (!canUpload && !isInProgress)
                    ? const Color(0xFFE5E7EB)
                    : null,
                borderRadius: BorderRadius.circular(18),
                boxShadow: tappable || isInProgress
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.38),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: tappable ? () => controller.upload(context, ref) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.transparent,
                  disabledForegroundColor: _inkSubtle,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isInProgress)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.cloud_upload_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: (!canUpload && !isInProgress)
                            ? _inkSubtle
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(
    String label,
    IconData icon, {
    bool required = false,
    bool done = false,
  }) =>
      Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: done
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x1F4A90E2), Color(0x334A90E2)],
                    ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: done
                  ? [
                      BoxShadow(
                        color: _successGreen.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Icon(
              done ? Icons.check_rounded : icon,
              size: 16,
              color: done ? Colors.white : _accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
              letterSpacing: -0.2,
            ),
          ),
          if (required && !done) ...[
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                fontSize: 14,
                color: _errorRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (done) ...[
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _successGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _successGreen,
                ),
              ),
            ),
          ],
        ],
      );

  Widget _fieldLabel(String label, {bool optional = false}) => Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _inkMuted,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: _canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'optional',
                style: TextStyle(
                  fontSize: 10,
                  color: _inkSubtle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        style: const TextStyle(
          fontSize: 14,
          color: _ink,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 18, color: _inkSubtle),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          filled: true,
          fillColor: _canvas,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: 13,
          ),
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
      );
}
