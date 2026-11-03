part of 'photo_detail_screen.dart';

class _EditPhotoSheet extends ConsumerStatefulWidget {
  const _EditPhotoSheet({required this.photo, required this.parentRef});

  final PhotoModel photo;
  final WidgetRef parentRef;

  @override
  ConsumerState<_EditPhotoSheet> createState() => _EditPhotoSheetState();
}

class _EditPhotoSheetState extends ConsumerState<_EditPhotoSheet> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _separator = Color(0xFFE3E7EE);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFDC2626);

  late final TextEditingController _noteController;
  late final TextEditingController _addressController;
  final _imagePicker = ImagePicker();

  bool _isSavingNote = false;
  final bool _isSavingAddress = false;
  bool _isReplacingImage = false;
  bool _isFetchingAddress = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.photo.note ?? '');

    // Combine address + ZIP into one field: "123 Main St, Dallas, TX 75001"
    final addr = widget.photo.address ?? '';
    final zip  = widget.photo.zipCode ?? '';
    var combined = addr;
    if (zip.isNotEmpty && !addr.contains(zip)) {
      combined = addr.isNotEmpty ? '$addr, $zip' : zip;
    }
    _addressController = TextEditingController(text: combined);

    // If address is missing or only has ZIP, auto-fetch from coordinates
    final needsGeocode = addr.isEmpty ||
        (addr == zip) ||
        (addr.trim() == zip.trim());
    if (needsGeocode &&
        widget.photo.latitude != 0 &&
        widget.photo.longitude != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFetchAddress());
    }
  }

  /// Reverse-geocode the photo's coordinates and populate the address field.
  Future<void> _autoFetchAddress() async {
    if (!mounted) return;
    setState(() => _isFetchingAddress = true);
    try {
      final address = await LocationService.reverseGeocode(
        widget.photo.latitude,
        widget.photo.longitude,
      );
      if (mounted && address != null && address.isNotEmpty) {
        setState(() {
          _addressController.text = address;
        });
      }
    } catch (_) {
      // Silently fail — user can type manually
    } finally {
      if (mounted) setState(() => _isFetchingAddress = false);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ── Snack helper ──────────────────────────────────────────────────────────
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _errorRed : _successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Save note ─────────────────────────────────────────────────────────────
  Future<void> _saveNote() async {
    final note = _noteController.text.trim();
    HapticFeedback.mediumImpact();
    setState(() => _isSavingNote = true);
    try {
      // Call the API
      await widget.parentRef.read(
        updatePhotoNoteProvider((widget.photo.id, note)).future,
      );
      // Invalidate and wait for the provider to finish refreshing so the
      // detail screen rebuilds with the new note before the sheet closes.
      widget.parentRef.invalidate(photosProvider);
      await widget.parentRef.read(photosProvider.future);
      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Note saved');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  // ── Replace image ─────────────────────────────────────────────────────────
  Future<void> _replaceImage(ImageSource source) async {
    // Check permissions
    if (source == ImageSource.camera) {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        _snack('Camera access blocked. Enable it in Settings.', isError: true);
        return;
      }
    } else {
      final status = await Permission.photos.status;
      if (status.isPermanentlyDenied) {
        _snack('Photo library access blocked. Enable it in Settings.',
            isError: true);
        return;
      }
      if (!status.isGranted && !status.isLimited) {
        final result = await Permission.photos.request();
        if (!result.isGranted && !result.isLimited) {
          _snack('Photo library permission required.', isError: true);
          return;
        }
      }
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;

      HapticFeedback.mediumImpact();
      setState(() => _isReplacingImage = true);

      await widget.parentRef.read(
        replacePhotoImageProvider((widget.photo.id, picked.path)).future,
      );
      widget.parentRef.invalidate(photosProvider);

      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Photo updated successfully');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _snack(
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isReplacingImage = false);
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Replace Photo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 16),
            _sourceOption(
              icon: Icons.camera_alt_rounded,
              label: 'Take a new photo',
              onTap: () {
                Navigator.pop(context);
                _replaceImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 10),
            _sourceOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                _replaceImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _accent),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
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
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Edit Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: _canvas,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Edit note ────────────────────────────────────────────
                  // NOTE FIRST — prevents accidental camera trigger when
                  // user taps the note field (was below Replace Photo before)
                  _label('Note'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [SentenceCaseInputFormatter()],
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Tap the mic and talk the note…',
                      hintStyle: const TextStyle(color: _inkSubtle),
                      filled: true,
                      fillColor: _canvas,
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: VoiceMicButton(
                          controller: _noteController,
                          mode: VoiceFillMode.append,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _accent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  NoteSuggestionChips(controller: _noteController),
                  const SizedBox(height: 10),
                  _saveBtn(
                    label: 'Save Note',
                    isLoading: _isSavingNote,
                    onTap: _saveNote,
                  ),
                  const SizedBox(height: 20),
                  _label('Address'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _canvas,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 16, color: _inkSubtle),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _addressController.text.trim().isEmpty
                                ? 'Address comes from the GPS geotag and cannot be changed.'
                                : _addressController.text.trim(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: _ink,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Divider before destructive/replace actions ────────────
                  const Divider(height: 1, color: _separator),
                  const SizedBox(height: 20),

                  _sectionCard(
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFF6B7280),
                    title: 'Location locked',
                    subtitle:
                        '${widget.photo.latitude.toStringAsFixed(5)}, ${widget.photo.longitude.toStringAsFixed(5)} · from geotag',
                    trailing: const Icon(
                      Icons.lock_outline_rounded,
                      color: _inkSubtle,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Replace image — at the BOTTOM to avoid accidental taps
                  _sectionCard(
                    icon: Icons.camera_alt_rounded,
                    iconColor: _accent,
                    title: 'Replace Photo',
                    subtitle: 'Swap the image with a new one',
                    trailing: _isReplacingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : const Icon(
                            Icons.chevron_right_rounded,
                            color: _inkSubtle,
                          ),
                    onTap: _isReplacingImage ? null : _showImageSourcePicker,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _inkMuted,
          letterSpacing: 0.2,
        ),
      );

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.lightImpact();
            onTap();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _inkSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );

  Widget _saveBtn({
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: isLoading ? null : () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: isLoading
                ? _accent.withValues(alpha: 0.5)
                : _accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for status summary timeline rows
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStep {
  const _SummaryStep({
    required this.status,
    required this.label,
    required this.icon,
    required this.timestamp,
    required this.color,
  });

  final String status;
  final String label;
  final IconData icon;
  final String? timestamp;
  final Color color;
}

/// Horizontal swipe between attempts. A mostly vertical drag stays with
/// the details scroll.
class _AttemptSwipe extends HorizontalDragGestureRecognizer {
  double _dx = 0;
  double _dy = 0;

  @override
  void addPointer(PointerDownEvent event) {
    _dx = 0;
    _dy = 0;
    super.addPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _dx += event.delta.dx;
      _dy += event.delta.dy;
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    if (_dx.abs() > 10 && _dx.abs() > _dy.abs()) {
      acceptGesture(pointer);
    } else {
      super.rejectGesture(pointer);
    }
  }
}

class _NewAttemptPeek extends StatelessWidget {
  const _NewAttemptPeek();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 36, color: Color(0xFF4A90E2)),
            SizedBox(height: 12),
            Text(
              'New attempt',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2130),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Release to start a new attempt for this profile',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF5C6778)),
            ),
          ],
        ),
      ),
    );
  }
}
