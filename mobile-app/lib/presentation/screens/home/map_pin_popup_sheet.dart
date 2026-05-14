import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../data/models/photo_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';

// ── Data class for a group of photos at the same pin, per profile ──────────
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

class _PinPopupSheetState extends ConsumerState<_PinPopupSheet> {
  // Design tokens
  static const _bg = Color(0xFF0F0E1A);
  static const _surface = Color(0xFF1A1830);
  static const _divider = Color(0x14FFFFFF);
  static const _textPrimary = Color(0xFFE2E8F0);
  static const _textMuted = Color(0xFF94A3B8);
  static const _accent = Color(0xFF6366F1);

  int _activeTab = 0;
  int _photoIdx = 0;
  bool _addingPhoto = false;

  // Add-photo state
  File? _pickedFile;
  final _noteCtrl = TextEditingController();
  int? _addProfileId;
  bool _uploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _addProfileId = widget.groups.isNotEmpty ? widget.groups[0].profileId : null;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int i) {
    setState(() {
      _activeTab = i;
      _photoIdx = 0;
      _addingPhoto = false;
      _pickedFile = null;
      _noteCtrl.clear();
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
      case 'rush': return 'Rush';
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
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedFile = File(picked.path);
      });
    }
  }

  Future<void> _uploadPhoto() async {
    if (_pickedFile == null || _addProfileId == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(uploadPhotoProvider({
        'filePath': _pickedFile!.path,
        'profileId': _addProfileId,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      }).future);
      if (mounted) {
        setState(() {
          _addingPhoto = false;
          _pickedFile = null;
          _noteCtrl.clear();
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
                color: Colors.white.withOpacity(0.2),
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
                            ? Colors.white.withOpacity(0.06)
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
                                  color.withOpacity(0.8),
                                  color.withOpacity(0.4),
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
                                    : Colors.white.withOpacity(0.4),
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
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${g.photos.length}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.4),
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
                  color: Colors.white.withOpacity(0.3),
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );

  // ── Photo carousel ────────────────────────────────────────────────────────
  Widget _buildCarousel(List<PhotoModel> photos, PhotoModel ph) => GestureDetector(
      onHorizontalDragEnd: (details) {
        if (photos.length <= 1) return;
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          setState(() => _photoIdx = (_photoIdx + 1) % photos.length);
        } else if (details.primaryVelocity! > 200) {
          setState(
            () => _photoIdx = (_photoIdx - 1 + photos.length) % photos.length,
          );
        }
      },
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            Image.network(
              ph.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: _surface,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 40,
                ),
              ),
            ),

            // Prev / Next arrows
            if (photos.length > 1) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _photoIdx =
                          (_photoIdx - 1 + photos.length) % photos.length,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _photoIdx = (_photoIdx + 1) % photos.length,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              // Dot indicators
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: _photoIdx == i ? 14 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _photoIdx == i
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    )),
                ),
              ),
              // Counter badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_photoIdx + 1}/${photos.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],

            // + Add Photo button (top-left)
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _addingPhoto = !_addingPhoto);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _addingPhoto
                        ? Colors.red.withOpacity(0.85)
                        : _accent.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _addingPhoto ? '✕ Cancel' : '📷 + Add Photo',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

  // ── Add photo form ────────────────────────────────────────────────────────
  Widget _buildAddPhotoForm() {
    final profilesAsync = ref.watch(profilesProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📍 Adding photo at this pin location',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 10),

          // Profile selector
          profilesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (profiles) => DropdownButtonFormField<int>(
              initialValue: _addProfileId,
              dropdownColor: _surface,
              style: const TextStyle(color: _textPrimary, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              items: profiles
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.name} (${p.serviceType})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _addProfileId = v),
            ),
          ),
          const SizedBox(height: 10),

          // Photo picker
          if (_pickedFile == null)
            Row(
              children: [
                Expanded(
                  child: _addPhotoBtn(
                    label: '📷 Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _addPhotoBtn(
                    label: '🖼 Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _pickedFile!,
                    height: 100,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pickedFile = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),

          // Note field
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Add a note… (optional)',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Upload button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_pickedFile != null && !_uploading) ? _uploadPhoto : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _pickedFile != null ? _accent : Colors.white12,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '↑ Upload to this pin',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoBtn({required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
        ),
      );

  // ── Photo detail ──────────────────────────────────────────────────────────
  Widget _buildPhotoDetail(PhotoModel ph, PinProfileGroup group) => Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Profiles at this pin" label
          Text(
            'Profiles at this pin',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.35),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),

          // Profile rows — all groups
          ...widget.groups.map((g) {
            final c = _svcColor(g.serviceType);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                context.push('/photo/${g.photos.first.id}');
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: c.withOpacity(0.5), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g.profileName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _svcLabel(g.serviceType),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // Timestamp + coords
          if (ph.timestamp != null)
            _metaRow(Icons.access_time_rounded, _formatTs(ph.timestamp)),
          _metaRow(
            Icons.location_on_rounded,
            '${ph.latitude.toStringAsFixed(5)}, ${ph.longitude.toStringAsFixed(5)}',
          ),
          if (ph.zipCode != null && ph.zipCode!.isNotEmpty)
            _metaRow(Icons.local_post_office_outlined, ph.zipCode!),
          if (ph.note != null && ph.note!.isNotEmpty)
            _metaRow(Icons.notes_rounded, ph.note!),

          const SizedBox(height: 12),

          // View Detail button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                context.push('/photo/${ph.id}');
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text(
                'View Full Detail',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );

  Widget _metaRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            Icon(icon, size: 13, color: _textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: _textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
