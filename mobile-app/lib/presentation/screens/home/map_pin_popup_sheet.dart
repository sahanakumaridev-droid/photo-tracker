import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/location_service.dart';
import '../../../core/utils/maps_launcher.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/photo_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';

// ── Data class for a group of photos at the same pin, per profile ──────────
part 'map_pin_popup_forms.dart';

class PinProfileGroup {
  PinProfileGroup({
    required this.profileId,
    required this.profileName,
    required this.serviceType,
    required this.photos,
  });
  final int profileId;
  final String profileName;
  final String serviceType;
  final List<PhotoModel> photos;
}

// ── Helper: build groups from a list of photos at the same location ─────────
List<PinProfileGroup> buildPinGroups(List<PhotoModel> photos) {
  final map = <int, PinProfileGroup>{};
  for (final ph in photos) {
    final pid = ph.profileId ?? 0;
    if (!map.containsKey(pid)) {
      map[pid] = PinProfileGroup(
        profileId: pid,
        profileName: ph.profileName ?? 'Unknown',
        serviceType: ph.serviceType ?? 'standard',
        photos: [],
      );
    }
    map[pid]!.photos.add(ph);
  }
  return map.values.toList();
}

// ── Show the sheet ───────────────────────────────────────────────────────────
void showPinPopupSheet(
  BuildContext context, {
  required List<PhotoModel> photos,
  required double lat,
  required double lng,
  required VoidCallback onUpdated,
}) {
  final groups = buildPinGroups(photos);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PinPopupSheet(
      groups: groups,
      lat: lat,
      lng: lng,
      onUpdated: onUpdated,
    ),
  );
}

// ── Sheet widget ─────────────────────────────────────────────────────────────
class _PinPopupSheet extends ConsumerStatefulWidget {
  const _PinPopupSheet({
    required this.groups,
    required this.lat,
    required this.lng,
    required this.onUpdated,
  });
  final List<PinProfileGroup> groups;
  final double lat;
  final double lng;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_PinPopupSheet> createState() => _PinPopupSheetState();
}

const _bg = Color(0xFFF2F4F7);
const _surface = Color(0xFFFFFFFF);
const _divider = Color(0xFFE3E7EE);
const _textPrimary = Color(0xFF1A2130);
const _textMuted = Color(0xFF5C6778);
const _accent = Color(0xFF4A90E2);
const double _kProfileProximityFt = 300;

class _PinPopupSheetState extends ConsumerState<_PinPopupSheet> {
  int _activeTab = 0;
  int _photoIdx = 0;
  bool _addingPhoto = false;

  // Reverse-geocoded address for this pin
  String? _pinAddress;
  bool _fetchingAddress = false;

  // Add-photo state
  File? _pickedFile;
  // EXIF capture time of the picked photo (falls back to now). Shown live as
  // a watermark and baked into the image on upload.
  String? _takenAt;
  final _noteCtrl = TextEditingController();
  // Only used as a fallback when this job has no file number yet (legacy pins
  // predating the required-file-number change) — normally it's carried
  // forward from the job's existing photos, below.
  final _fileNumberCtrl = TextEditingController();
  int? _addProfileId;
  bool _uploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _addProfileId = widget.groups.isNotEmpty ? widget.groups[0].profileId : null;
    // File Number's fallback field affects the submit button's enabled
    // state, so it needs to rebuild live as the user types.
    _fileNumberCtrl.addListener(() => setState(() {}));
    // Auto reverse-geocode the pin location
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPinAddress());
  }

  /// The dispatcher-assigned file number already on record for [profileId]
  /// (carried over from any of its existing photos, at this pin or
  /// elsewhere), so adding another attempt never asks the user to retype it.
  /// Falls back to null for a profile with no prior file number (legacy data
  /// predating the required-file-number change).
  String? _existingFileNumberFor(int? profileId) {
    if (profileId == null) return null;
    final photos = ref.read(photosProvider).valueOrNull ?? const [];
    for (final p in photos) {
      if (p.profileId != profileId) continue;
      final fn = p.fileNumber;
      if (fn != null && fn.isNotEmpty) return fn;
    }
    return null;
  }

  Future<void> _fetchPinAddress() async {
    if (!mounted) return;
    setState(() => _fetchingAddress = true);
    try {
      final address = await LocationService.reverseGeocode(widget.lat, widget.lng);
      if (mounted && address != null && address.isNotEmpty) {
        setState(() => _pinAddress = address);
      }
    } catch (_) {
      // Silently fail
    } finally {
      if (mounted) setState(() => _fetchingAddress = false);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _fileNumberCtrl.dispose();
    super.dispose();
  }

  // Profiles whose saved address is within 300 ft of this pin.
  Set<int> _nearbyProfileIds() {
    final profiles = ref.read(profilesProvider).valueOrNull ?? const [];
    final ids = <int>{};
    for (final p in profiles) {
      if (p.latitude == null || p.longitude == null) continue;
      final km = LocationService.calculateDistance(
          widget.lat, widget.lng, p.latitude!, p.longitude!);
      if (km * 3280.84 <= _kProfileProximityFt) ids.add(p.id);
    }
    return ids;
  }

  void _switchTab(int i) {
    setState(() {
      _activeTab = i;
      _photoIdx = 0;
      _addingPhoto = false;
      _pickedFile = null;
      _takenAt = null;
      _noteCtrl.clear();
      _fileNumberCtrl.clear();
      _addProfileId = widget.groups[i].profileId;
    });
  }

  Color _svcColor(String t) {
    switch (t.toLowerCase()) {
      case 'rush': return const Color(0xFFEF4444);
      case 'airport': return const Color(0xFF0EA5E9);
      default: return const Color(0xFF10B981);
    }
  }

  String _svcLabel(String t) {
    switch (t.toLowerCase()) {
      case 'rush': return 'ASAP';
      case 'airport': return 'Airport';
      default: return 'Standard';
    }
  }

  String _formatTs(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return ts;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
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
  }

  Future<void> _uploadPhoto() async {
    if (_pickedFile == null || _addProfileId == null) return;
    final fileNumber = _existingFileNumberFor(_addProfileId) ??
        _fileNumberCtrl.text.trim();
    if (fileNumber.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final gps = await LocationService.getCurrentLocation() ??
          await LocationService.getLastKnownLocation();
      if (!mounted) return;
      if (gps == null) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read GPS for this attempt.')),
        );
        return;
      }
      final tooFar = LocationService.attemptTooFarMessage(
        gpsLat: gps.latitude,
        gpsLng: gps.longitude,
        jobLat: widget.lat,
        jobLng: widget.lng,
        gpsAccuracyMeters: gps.accuracy,
      );
      if (tooFar != null) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tooFar)),
        );
        return;
      }
      final takenAt = _takenAt ?? DateTime.now().toUtc().toIso8601String();
      // Upload the ORIGINAL photo; the watermark is a display overlay + export
      // re-bake now, so baking here would double-stamp beneath the overlay.
      final watermarked = _pickedFile!;
      await ref.read(uploadPhotoProvider({
        'filePath': watermarked.path,
        'profileId': _addProfileId,
        'latitude': gps.latitude,
        'longitude': gps.longitude,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'takenAt': takenAt,
        'fileNumber': fileNumber,
      }).future);
      if (mounted) {
        setState(() {
          _addingPhoto = false;
          _pickedFile = null;
          _takenAt = null;
          _noteCtrl.clear();
          _fileNumberCtrl.clear();
        });
        widget.onUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.groups[_activeTab];
    final photos = group.photos;
    final ph = photos[_photoIdx];
    final totalPhotos = widget.groups.fold(0, (s, g) => s + g.photos.length);

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Profile tabs
          _buildTabs(totalPhotos),

          // Photo carousel
          _buildCarousel(photos, ph),

          // Add photo form OR photo detail
          if (_addingPhoto)
            _buildAddPhotoForm()
          else
            _buildPhotoDetail(ph, group),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  // ── Profile tabs ──────────────────────────────────────────────────────────
  Widget _buildTabs(int totalPhotos) => Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.groups.length, (i) {
                  final g = widget.groups[i];
                  final color = _svcColor(g.serviceType);
                  final isActive = _activeTab == i;
                  return GestureDetector(
                    onTap: () => _switchTab(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: isActive ? color : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Avatar
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  color.withValues(alpha: 0.8),
                                  color.withValues(alpha: 0.4),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: isActive ? color : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                g.profileName[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Name
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 70),
                            child: Text(
                              g.profileName.split(' ')[0],
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Count badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? color
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${g.photos.length}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          // Total count
          if (widget.groups.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '$totalPhotos total',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.3),
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );

  // ── Photo carousel ────────────────────────────────────────────────────────
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});
}
