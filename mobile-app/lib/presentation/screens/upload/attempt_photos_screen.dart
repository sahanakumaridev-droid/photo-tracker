import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/photo_stamp.dart';
import 'attempt_draft_controller.dart';

/// Dedicated Photos screen, pushed from the Resume Attempt hub. Body is the
/// old form's photo section + capture-time card, rebound to the shared
/// [AttemptDraftController]. No footer upload button — the back button is
/// the only exit; autosave already fires on every change via the controller.
class AttemptPhotosScreen extends StatelessWidget {
  const AttemptPhotosScreen({super.key, required this.controller});

  final AttemptDraftController controller;

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _accentMid = Color(0xFF64B5F6);
  static const LinearGradient _btnGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF64B5F6), Color(0xFF4A90E2)],
  );

  @override
  Widget build(BuildContext context) {
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
          'Photos',
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
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _buildPhotoSection(context),
          ),
        ),
      ),
    );
  }

  // ── Photo section (multi-photo) ──────────────────────────────────────────
  Widget _buildPhotoSection(BuildContext context) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Photos',
              Icons.camera_alt_rounded,
              required: true,
              done: controller.hasPhoto,
            ),
            if (controller.existingPhotoCount > 0) ...[
              const SizedBox(height: 10),
              _existingPhotoBanner(),
            ],
            if (controller.selectedImages.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${controller.selectedImages.length} photo'
                '${controller.selectedImages.length > 1 ? 's' : ''} selected'
                ' · tap to preview the timestamp',
                style: const TextStyle(fontSize: 12, color: _inkSubtle),
              ),
            ],
            const SizedBox(height: 12),
            // Thumbnail strip — shown when at least one photo is selected.
            if (controller.selectedImages.isNotEmpty)
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _showPhotoPreview(context, i),
                    child: SizedBox(
                      width: 110,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 110,
                              height: 130,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    controller.selectedImages[i],
                                    fit: BoxFit.cover,
                                    cacheWidth: 320,
                                  ),
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
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => controller.removeImage(i),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (controller.selectedImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              _captureTimeCard(),
            ],
            if (controller.selectedImages.isEmpty)
              GestureDetector(
                onTap: () => controller.pickImage(context, ImageSource.camera),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.22),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded,
                          size: 32, color: _accent.withValues(alpha: 0.7)),
                      const SizedBox(height: 10),
                      const Text('Add Photos',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                      const SizedBox(height: 4),
                      const Text('Camera or gallery · multiple supported',
                          style:
                              TextStyle(fontSize: 12, color: _inkSubtle)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _srcBtn(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () =>
                        controller.pickImage(context, ImageSource.camera),
                    primary: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _srcBtn(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () =>
                        controller.pickImage(context, ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // Read-only banner shown when resuming a real, already-saved server
  // Attempt with photos it already has — those remote photos can't be
  // loaded into this screen's local-file picker, so their count is
  // surfaced here instead of thumbnails.
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
              '$count photo${count > 1 ? 's' : ''} already uploaded — '
              'add more below',
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

  // Always-visible timestamp field: shows the photo's capture time (EXIF) the
  // moment a photo is added — this is exactly what gets baked into the
  // watermark on upload.
  Widget _captureTimeCard() {
    final iso =
        controller.takenAts.isNotEmpty ? controller.takenAts.first : null;
    final label = iso == null ? 'Reading photo time…' : formatStamp(iso);
    final multi = controller.selectedImages.length > 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PHOTO TIMESTAMP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (multi)
                  const Text(
                    'Each photo keeps its own capture time',
                    style: TextStyle(fontSize: 11, color: _inkSubtle),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'on watermark',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _srcBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: primary ? _btnGradient : null,
            color: primary ? null : _surface,
            borderRadius: BorderRadius.circular(14),
            border: primary
                ? null
                : Border.all(
                    color: _accent.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: primary ? Colors.white : _accentMid),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.white : _accentMid,
                ),
              ),
            ],
          ),
        ),
      );

  // Full-size preview showing the exact watermark (timestamp + address) that
  // will be baked into the photo at upload time.
  void _showPhotoPreview(BuildContext context, int index) {
    if (index < 0 || index >= controller.selectedImages.length) return;
    HapticFeedback.lightImpact();
    final address = controller.addressController.text.trim();
    final takenAtIso =
        index < controller.takenAts.length ? controller.takenAts[index] : null;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogCtx) => Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(dialogCtx).size.height * 0.8,
                maxWidth: MediaQuery.of(dialogCtx).size.width * 0.95,
              ),
              child: InteractiveViewer(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(controller.selectedImages[index]),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                        child: WatermarkBar(
                          takenAtIso: takenAtIso,
                          address: address,
                          fileNumber: controller.fileNumberController.text,
                          profileName: controller.selectedProfile?.name,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(dialogCtx).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(dialogCtx),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(dialogCtx).padding.bottom + 16,
            child: Text(
              'Timestamp read from the photo · stamped on upload',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
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
                color: Color(0xFFEF4444),
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
                color: const Color(0xFF10B981).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ],
      );
}
