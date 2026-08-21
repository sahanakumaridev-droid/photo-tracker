import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/storage/upload_queue.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../../widgets/common/create_profile_dialog.dart';

/// Bottom sheet shown when user taps empty map space.
/// Lets them upload a photo at the tapped coordinates.
void showMapUploadSheet(
  BuildContext context, {
  required double lat,
  required double lng,
  required VoidCallback onUploaded,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MapUploadSheet(lat: lat, lng: lng, onUploaded: onUploaded),
  );
}

class _MapUploadSheet extends ConsumerStatefulWidget {
  const _MapUploadSheet({
    required this.lat,
    required this.lng,
    required this.onUploaded,
  });
  final double lat;
  final double lng;
  final VoidCallback onUploaded;

  @override
  ConsumerState<_MapUploadSheet> createState() => _MapUploadSheetState();
}

class _MapUploadSheetState extends ConsumerState<_MapUploadSheet> {
  // Design tokens
  static const _canvas = Color(0xFFF2F4F7);
  static const _surface = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF1A2130);
  static const _inkMuted = Color(0xFF5C6778);
  static const _inkSubtle = Color(0xFF8B95A5);
  static const _separator = Color(0xFFE3E7EE);
  static const _accent = Color(0xFF4A90E2);
  static const _accentSoft = Color(0x1F4A90E2);
  static const _errorRed = Color(0xFFDC2626);
  // Radius used to surface "Nearby" profiles first in the picker — matches
  // the main Upload tab's profile picker.
  static const double _kProfileProximityFt = 200;

  ProfileModel? _selectedProfile;
  // Priority level is chosen per-upload here (not stored on the profile).
  String _selectedCategory = kDefaultCategory;
  File? _pickedFile;
  // Capture time read from the photo's EXIF (falls back to now). Shown live
  // as a watermark and baked into the image on upload.
  String? _takenAt;
  final _noteCtrl = TextEditingController();
  final _fileNumberCtrl = TextEditingController();
  bool _uploading = false;
  String? _error;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // File Number is required — the submit button's enabled state depends on
    // it, so it needs to rebuild live as the user types.
    _fileNumberCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _fileNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    // Clear any stale error from a previous failed attempt — otherwise a
    // successful pick here still leaves the old error banner on screen.
    if (_error != null) setState(() => _error = null);
    try {
      // Full resolution so EXIF (capture date) survives; watermark downscales.
      final picked = await _picker.pickImage(source: source);
      if (picked != null && mounted) {
        setState(() {
          _pickedFile = File(picked.path);
          // Show a provisional time immediately; refine from EXIF below.
          _takenAt = DateTime.now().toUtc().toIso8601String();
        });
        final captured = await readCaptureTimeIso(File(picked.path));
        if (mounted) setState(() => _takenAt = captured);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open image picker.');
      }
    }
  }

  Future<void> _upload() async {
    final fileNumber = _fileNumberCtrl.text.trim();
    if (_pickedFile == null || _selectedProfile == null) return;
    if (fileNumber.isEmpty) {
      setState(() => _error = 'Please enter a file number');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() { _uploading = true; _error = null; });
    final takenAt = _takenAt ?? DateTime.now().toUtc().toIso8601String();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final svc = _selectedCategory;
    // Upload the ORIGINAL photo. The watermark caption is drawn as a display
    // overlay in the feed/detail screens and re-baked at export time, so baking
    // on upload here would double-stamp beneath the overlay.
    final watermarked = _pickedFile!;
    // ENQUEUE-FIRST: persist to the durable queue BEFORE the network call, so a
    // signal drop or an app-kill mid-upload auto-resumes on its own. takenAt +
    // geotag are captured once here and never regenerated. The auto-drainer is
    // paused so it can't race this upload and double-send.
    UploadQueueService.instance.pauseAutoProcess();
    final queued = await UploadQueueService.instance.enqueue(
      sourceFile: watermarked,
      profileId: _selectedProfile!.id,
      latitude: widget.lat,
      longitude: widget.lng,
      takenAt: takenAt,
      note: note,
      category: svc,
      fileNumber: fileNumber,
      profileName: _selectedProfile!.name,
    );
    try {
      await ref.read(uploadPhotoProvider({
        'filePath': watermarked.path,
        'profileId': _selectedProfile!.id,
        'fileNumber': fileNumber,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'note': note,
        'category': svc,
        'takenAt': takenAt,
      }).future);
      // Sent — drop it from the queue so the drainer can't re-send it.
      await UploadQueueService.instance.remove(queued.id);
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
        widget.onUploaded();
      }
    } catch (e) {
      // No network error pop-up: it's already in the offline queue (above) and
      // will upload automatically when signal returns.
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
        widget.onUploaded();
      }
    } finally {
      UploadQueueService.instance.resumeAutoProcess();
      if (mounted) setState(() => _uploading = false);
    }
  }

  // Profile IDs with a photo within _kProfileProximityMi of the tapped
  // location — surfaced first in the picker, matching the main Upload tab.
  Set<int> _nearbyProfileIds() {
    final photos = ref.read(photosProvider).valueOrNull ?? const [];
    final ids = <int>{};
    for (final p in photos) {
      if (p.profileId == null) continue;
      final km = LocationService.calculateDistance(
          widget.lat, widget.lng, p.latitude, p.longitude);
      if (km * 3280.84 <= _kProfileProximityFt) ids.add(p.profileId!);
    }
    return ids;
  }

  Widget _profileTile(ProfileModel p) {
    final selected = _selectedProfile?.id == p.id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedProfile = p;
          if (!companyOrDefault(p.company).allowsPriority(_selectedCategory)) {
            _selectedCategory = defaultPriorityForCompany(p.company);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : _canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? _accent : _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  p.name[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : _accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _accent : _ink,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: _accent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final canUpload = _pickedFile != null &&
        _selectedProfile != null &&
        _fileNumberCtrl.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upload at this location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _inkSubtle,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _inkSubtle),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 20, color: _separator),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile selector
                  const Text(
                    'Select Profile',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _inkMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  profilesAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      ),
                    ),
                    error: (e, _) => const Text(
                      'Failed to load profiles',
                      style: TextStyle(color: _errorRed, fontSize: 13),
                    ),
                    data: (profiles) {
                      if (profiles.isEmpty) return _noProfilesState();
                      final nearbyIds = _nearbyProfileIds();
                      final nearby = profiles
                          .where((p) => nearbyIds.contains(p.id))
                          .toList();
                      // Only nearby profiles are selectable here — this sheet
                      // is for tagging a photo at a specific tapped location,
                      // so profiles elsewhere aren't relevant. No fallback to
                      // the full roster when nothing is within range — the
                      // empty state below prompts creating a new profile.
                      if (nearby.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _noNearbyProfilesState(),
                            const SizedBox(height: 8),
                            _addProfileButton(),
                          ],
                        );
                      }
                      final items = <Object>[
                        'Nearby · within ${_kProfileProximityFt.toInt()} ft',
                        ...nearby,
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 220),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: items.length,
                              separatorBuilder: (_, i) => items[i] is String
                                  ? const SizedBox()
                                  : const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final item = items[i];
                                if (item is String) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, bottom: 6),
                                    child: Text(
                                      item.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: _inkSubtle,
                                      ),
                                    ),
                                  );
                                }
                                return _profileTile(item as ProfileModel);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _addProfileButton(),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Priority level — chosen per-upload (same as the full upload
                  // screen); not stored on the profile.
                  const Text(
                    'Priority Level',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _inkMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _categoryPicker(),

                  const SizedBox(height: 16),

                  // File Number — required, dispatcher-assigned.
                  Row(
                    children: [
                      const Text(
                        'File Number',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _inkMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '*',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _errorRed.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fileNumberCtrl,
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'e.g. 24-00123',
                      hintStyle: const TextStyle(
                        color: _inkSubtle,
                        fontSize: 14,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.tag_rounded,
                          size: 18,
                          color: _inkSubtle,
                        ),
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
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(builder: (_) {
                      final isNa =
                          _fileNumberCtrl.text.trim().toUpperCase() ==
                              kFileNumberNA;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (isNa) {
                              _fileNumberCtrl.clear();
                            } else {
                              _fileNumberCtrl.text = kFileNumberNA;
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
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
                      );
                    }),
                  ),

                  const SizedBox(height: 16),

                  // Photo picker
                  const Text(
                    'Photo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _inkMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_pickedFile == null)
                    Row(
                      children: [
                        Expanded(
                          child: _srcBtn(
                            icon: Icons.camera_alt_rounded,
                            label: 'Camera',
                            onTap: () => _pickImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _srcBtn(
                            icon: Icons.photo_library_outlined,
                            label: 'Gallery',
                            onTap: () => _pickImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    )
                  else
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 140,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_pickedFile!,
                                    fit: BoxFit.cover, cacheWidth: 720),
                                // Live timestamp watermark — matches upload.
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: WatermarkBar(takenAtIso: _takenAt),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _pickedFile = null;
                              _takenAt = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 14),

                  // Note
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [SentenceCaseInputFormatter()],
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Tap the mic or type a note…',
                      hintStyle: const TextStyle(
                        color: _inkSubtle,
                        fontSize: 14,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: _inkSubtle,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      suffixIcon: VoiceMicButton(
                        controller: _noteCtrl,
                        mode: VoiceFillMode.append,
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
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 14,
                          color: _errorRed,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Upload button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (canUpload && !_uploading) ? _upload : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canUpload ? _accent : _separator,
                        foregroundColor:
                            canUpload ? Colors.white : _inkSubtle,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _uploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload_outlined, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  '↑ Upload here',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddProfile() async {
    final created = await showCreateProfileDialog(context);
    // profilesProvider is watched in build(), so the new profile appears in
    // the list automatically; pre-select it for the user.
    if (created != null && mounted) {
      setState(() {
        _selectedProfile = created;
        if (!companyOrDefault(created.company)
            .allowsPriority(_selectedCategory)) {
          _selectedCategory = defaultPriorityForCompany(created.company);
        }
      });
    }
  }

  Widget _categoryPicker() {
    final companyId = _selectedProfile?.company;
    final categories = priorityCategoriesForCompany(companyId);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((c) {
        final selected = _selectedCategory == c.value;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCategory = c.value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? c.color : c.softColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? c.color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon,
                    size: 14, color: selected ? Colors.white : c.color),
                const SizedBox(width: 6),
                Text(
                  c.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : c.color,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _addProfileButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _openAddProfile();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: _accentSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18, color: _accent),
            SizedBox(width: 6),
            Text(
              'Add Profile',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noProfilesState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _separator, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: _accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_add_outlined, size: 24, color: _accent),
          ),
          const SizedBox(height: 10),
          const Text(
            'No profiles yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create a profile first to upload photos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _inkSubtle),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openAddProfile,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(
                'Create Profile',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noNearbyProfilesState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _separator, width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.location_searching_rounded,
              size: 22, color: _inkSubtle),
          const SizedBox(height: 8),
          Text(
            'No profiles within ${_kProfileProximityFt.toInt()} ft of '
            'this location',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create a new profile here instead.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _inkSubtle),
          ),
        ],
      ),
    );
  }

  Widget _srcBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ],
          ),
        ),
      );
}
