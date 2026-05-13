import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';

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
  static const _ink = Color(0xFF0D1117);
  static const _inkMuted = Color(0xFF4B5563);
  static const _inkSubtle = Color(0xFF9CA3AF);
  static const _separator = Color(0xFFE5E7EB);
  static const _accent = Color(0xFF5B5BD6);
  static const _accentSoft = Color(0xFFEEEEFD);
  static const _errorRed = Color(0xFFDC2626);

  ProfileModel? _selectedProfile;
  File? _pickedFile;
  final _noteCtrl = TextEditingController();
  bool _uploading = false;
  String? _error;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked != null && mounted) {
        setState(() => _pickedFile = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open image picker.');
      }
    }
  }

  Future<void> _upload() async {
    if (_pickedFile == null || _selectedProfile == null) return;
    HapticFeedback.mediumImpact();
    setState(() { _uploading = true; _error = null; });
    try {
      await ref.read(uploadPhotoProvider({
        'filePath': _pickedFile!.path,
        'profileId': _selectedProfile!.id,
        'latitude': widget.lat,
        'longitude': widget.lng,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      }).future);
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
        widget.onUploaded();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Color _svcColor(String t) {
    switch (t.toLowerCase()) {
      case 'rush': return const Color(0xFFDC2626);
      case 'airport': return const Color(0xFF0284C7);
      default: return const Color(0xFF059669);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final canUpload = _pickedFile != null && _selectedProfile != null;

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
                    data: (profiles) => ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: profiles.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final p = profiles[i];
                          final selected = _selectedProfile?.id == p.id;
                          final color = _svcColor(p.serviceType);
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedProfile = p);
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
                                  color: selected
                                      ? _accent
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? _accent
                                          : color.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        p.name[0].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : color,
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
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected ? _accent : _ink,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      p.serviceType,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: color,
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
                        },
                      ),
                    ),
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
                            icon: Icons.photo_library_rounded,
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
                          child: Image.file(
                            _pickedFile!,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _pickedFile = null),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
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
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Add a note… (optional)',
                      hintStyle: const TextStyle(
                        color: _inkSubtle,
                        fontSize: 14,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.notes_rounded,
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
                                Icon(Icons.cloud_upload_rounded, size: 18),
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
