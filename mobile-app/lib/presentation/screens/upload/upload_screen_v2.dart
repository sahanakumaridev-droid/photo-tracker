import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/location_service.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import 'location_picker_map.dart';

class UploadScreenV2 extends ConsumerStatefulWidget {
  const UploadScreenV2({super.key});

  @override
  ConsumerState<UploadScreenV2> createState() => _UploadScreenV2State();
}

class _UploadScreenV2State extends ConsumerState<UploadScreenV2> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF5B5BD6);
  static const Color _accentSoft = Color(0xFFEEEEFD);
  static const Color _successGreen = Color(0xFF059669);
  static const Color _errorRed = Color(0xFFDC2626);

  // ── State ─────────────────────────────────────────────────────────────────
  File? _selectedImage;
  ProfileModel? _selectedProfile;
  double? _latitude;
  double? _longitude;
  bool _isLoadingLocation = false;
  bool _locationError = false;
  bool _isEditingAddress = false;
  bool _isUploading = false;

  final _noteController = TextEditingController();
  final _zipController = TextEditingController();
  final _addressController = TextEditingController();
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Small delay so the screen renders first, then fetch location
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLocation());
  }

  @override
  void dispose() {
    _noteController.dispose();
    _zipController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = false;
      _addressController.clear();
      _zipController.clear();
    });
    try {
      // Request permission first
      final granted = await LocationService.requestLocationPermission();
      if (!granted) {
        debugPrint('[Location] Permission not granted');
        if (mounted) setState(() => _locationError = true);
        return;
      }

      // Try last-known position first for a fast first paint
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
        if (pos != null && mounted) {
          setState(() {
            _latitude = pos!.latitude;
            _longitude = pos.longitude;
          });
        }
      } catch (_) {}

      // Always fetch a fresh high-accuracy fix
      final freshPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );
      debugPrint('[Location] fresh pos=${freshPos.latitude},${freshPos.longitude}');

      if (mounted) {
        setState(() {
          _latitude = freshPos.latitude;
          _longitude = freshPos.longitude;
        });

        final geo = await LocationService.reverseGeocode(
          freshPos.latitude,
          freshPos.longitude,
        );
        debugPrint('[Location] geo=$geo');

        if (mounted) {
          setState(() {
            if (geo.address != null && geo.address!.isNotEmpty) {
              _addressController.text = geo.address!;
            }
            if (geo.zip != null && geo.zip!.isNotEmpty) {
              _zipController.text = geo.zip!;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[Location] error: $e');
      if (mounted) setState(() => _locationError = true);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Map picker ────────────────────────────────────────────────────────────
  Future<void> _openMapPicker() async {
    final initial = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : null;

    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerMap(initial: initial),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      _isLoadingLocation = true;
      _locationError = false;
    });

    // Reverse-geocode the picked point
    try {
      final geo = await LocationService.reverseGeocode(
        picked.latitude,
        picked.longitude,
      );
      if (mounted) {
        setState(() {
          if (geo.address != null && geo.address!.isNotEmpty) {
            _addressController.text = geo.address!;
          }
          if (geo.zip != null && geo.zip!.isNotEmpty) {
            _zipController.text = geo.zip!;
          }
        });
      }
    } catch (e) {
      debugPrint('[MapPicker] reverse geocode error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Camera / Gallery ──────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();

    if (source == ImageSource.camera) {
      await _pickFromCamera();
    } else {
      await _pickFromGallery();
    }
  }

  Future<void> _pickFromCamera() async {
    // Check camera permission explicitly on both iOS and Android
    final status = await Permission.camera.status;

    if (status.isPermanentlyDenied) {
      if (mounted) {
        _showSnack(
          'Camera access blocked. Enable it in Settings.',
          isError: true,
          settingsAction: true,
        );
      }
      return;
    }

    if (status.isDenied || status.isRestricted) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        if (mounted) {
          _showSnack(
            'Camera permission is required to take photos.',
            isError: true,
            settingsAction: result.isPermanentlyDenied,
          );
        }
        return;
      }
    }

    await _openPicker(ImageSource.camera);
  }

  Future<void> _pickFromGallery() async {
    // On iOS 14+, image_picker uses PHPickerViewController which does NOT
    // require full photo library permission — it works with limited access
    // too. We must treat isLimited as granted, otherwise the gallery never
    // opens even when the user tapped "Select Photos" in the system dialog.
    final status = await Permission.photos.status;

    if (status.isPermanentlyDenied) {
      if (mounted) {
        _showSnack(
          'Photo library access blocked. Enable it in Settings.',
          isError: true,
          settingsAction: true,
        );
      }
      return;
    }

    // isGranted OR isLimited (iOS 14 "Select Photos") → proceed directly
    if (status.isGranted || status.isLimited) {
      await _openPicker(ImageSource.gallery);
      return;
    }

    // isDenied / isRestricted / notDetermined → request
    final result = await Permission.photos.request();

    // isLimited counts as success — user picked specific photos
    if (result.isGranted || result.isLimited) {
      await _openPicker(ImageSource.gallery);
    } else {
      if (mounted) {
        _showSnack(
          'Photo library permission is required to pick photos.',
          isError: true,
          settingsAction: result.isPermanentlyDenied,
        );
      }
    }
  }

  Future<void> _openPicker(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked != null && mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _selectedImage = File(picked.path));
      }
    } on PlatformException catch (e) {
      debugPrint('[Picker] PlatformException: ${e.code} – ${e.message}');
      final isPermissionError = e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied' ||
          e.code == 'PHPickerViewController/permission_denied';
      if (mounted) {
        _showSnack(
          isPermissionError
              ? 'Permission denied. Enable in Settings.'
              : 'Could not open '
                  '${source == ImageSource.camera ? "camera" : "gallery"}'
                  ': ${e.message}',
          isError: true,
          settingsAction: isPermissionError,
        );
      }
    } on Exception catch (e) {
      debugPrint('[Picker] error: $e');
      if (mounted) {
        _showSnack(
          'Could not open '
          '${source == ImageSource.camera ? "camera" : "gallery"}',
          isError: true,
        );
      }
    }
  }

  void _showSnack(
    String msg, {
    bool isError = false,
    bool settingsAction = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
        action: settingsAction
            ? const SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: openAppSettings,
              )
            : null,
      ),
    );
  }

  // ── Upload ────────────────────────────────────────────────────────────────
  Future<void> _upload() async {
    if (_selectedImage == null) {
      _showSnack('Please select a photo first', isError: true);
      return;
    }
    if (_selectedProfile == null) {
      _showSnack('Please select a profile', isError: true);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showSnack('Location required. Tap refresh to retry.', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isUploading = true);

    try {
      await ref.read(uploadPhotoProvider({
        'filePath': _selectedImage!.path,
        'profileId': _selectedProfile!.id,
        'latitude': _latitude,
        'longitude': _longitude,
        'zipCode': _zipController.text.trim().isEmpty
            ? null
            : _zipController.text.trim(),
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      }).future);

      if (mounted) {
        HapticFeedback.heavyImpact();
        _showSnack('Photo uploaded successfully');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final canUpload = _selectedImage != null &&
        _selectedProfile != null &&
        _latitude != null &&
        !_isUploading;

    return Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPhotoSection(),
                  const SizedBox(height: 14),
                  _buildProfileSection(profilesAsync),
                  const SizedBox(height: 14),
                  _buildLocationSection(),
                  const SizedBox(height: 14),
                  _buildDetailsSection(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildUploadBar(canUpload),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
        color: _surface,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                  ),
                  color: _inkMuted,
                  onPressed: () => context.pop(),
                ),
                const Expanded(
                  child: Text(
                    'New Upload',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Photo section ─────────────────────────────────────────────────────────
  Widget _buildPhotoSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Photo', Icons.camera_alt_rounded, required: true),
            const SizedBox(height: 12),
            // Preview — tap opens camera directly
            GestureDetector(
              onTap: _selectedImage == null
                  ? () => _pickImage(ImageSource.camera)
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _selectedImage != null
                    ? Stack(
                        children: [
                          Image.file(
                            _selectedImage!,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: GestureDetector(
                              onTap: () => _pickImage(ImageSource.camera),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Retake',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _canvas,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: _accentSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 30,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Tap to take a photo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Opens camera',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: _inkSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            // Buttons — Camera primary, Gallery secondary
            Row(
              children: [
                Expanded(
                  child: _srcBtn(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                    primary: true,
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
            ),
          ],
        ),
      );

  Widget _srcBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: primary ? _accent : _canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: primary ? Colors.white : _accent),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : _accent,
                ),
              ),
            ],
          ),
        ),
      );

  // ── Profile section ───────────────────────────────────────────────────────
  Widget _buildProfileSection(AsyncValue<List<ProfileModel>> profilesAsync) =>
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Profile',
              Icons.person_rounded,
              required: true,
            ),
            const SizedBox(height: 12),
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
              error: (e, _) => _errorBox('Failed to load profiles'),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return _errorBox(
                    'No profiles found. Create one in Settings.',
                  );
                }
                // Show selected profile or tap-to-pick row
                return GestureDetector(
                  onTap: () => _showProfilePicker(profiles),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedProfile != null
                          ? _accentSoft
                          : _canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: _selectedProfile != null
                          ? Border.all(color: _accent, width: 1.5)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _selectedProfile != null
                                ? _accent
                                : _inkSubtle.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: _selectedProfile != null
                                ? Text(
                                    _selectedProfile!.name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_outline_rounded,
                                    size: 18,
                                    color: _inkSubtle,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedProfile?.name ?? 'Select a profile',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _selectedProfile != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _selectedProfile != null
                                  ? _accent
                                  : _inkSubtle,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _selectedProfile != null
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

  void _showProfilePicker(List<ProfileModel> profiles) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
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
                    '${profiles.length} profiles',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: profiles.length,
                itemBuilder: (_, i) {
                  final p = profiles[i];
                  final sel = _selectedProfile?.id == p.id;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedProfile = p);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? _accentSoft
                            : _canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: sel
                            ? Border.all(color: _accent, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: sel
                                  ? _accent
                                  : _accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                p.name[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : _accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: sel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: sel ? _accent : _ink,
                                  ),
                                ),
                                Text(
                                  _svcLabel(p.serviceType),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _inkSubtle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: _accent,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _svcLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return 'Rush service';
      case 'airport':
        return 'Airport service';
      default:
        return 'Standard service';
    }
  }

  // ── Location section ──────────────────────────────────────────────────────
  Widget _buildLocationSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: _sectionLabel(
                    'Location',
                    Icons.location_on_rounded,
                    required: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Action buttons row
            Row(
              children: [
                // Pick on map button
                GestureDetector(
                  onTap: _openMapPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 13, color: _accent),
                        SizedBox(width: 4),
                        Text(
                          'Pick on Map',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _fetchLocation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _canvas,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 13,
                          color: _isLoadingLocation ? _inkSubtle : _accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isLoadingLocation ? 'Locating…' : 'Refresh',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isLoadingLocation
                                ? _inkSubtle
                                : _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Loading ──────────────────────────────────────────────
            if (_isLoadingLocation)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Getting your location…',
                      style: TextStyle(fontSize: 13, color: _inkMuted),
                    ),
                  ],
                ),
              )

            // ── Error ────────────────────────────────────────────────
            else if (_locationError || _latitude == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.location_off_rounded,
                      size: 18,
                      color: _errorRed,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Location unavailable. Tap Refresh to retry.',
                        style: TextStyle(fontSize: 13, color: _errorRed),
                      ),
                    ),
                  ],
                ),
              )

            // ── Success ──────────────────────────────────────────────
            else ...[
              // ── Address (editable) ───────────────────────────────
              _fieldLabel('Address', optional: false),
              const SizedBox(height: 6),
              Stack(
                children: [
                  TextField(
                    controller: _addressController,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _ink,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Street, City, State, ZIP',
                      hintStyle: const TextStyle(
                        color: _inkSubtle,
                        fontSize: 13,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.home_work_outlined,
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
                      contentPadding: const EdgeInsets.fromLTRB(
                        0,
                        12,
                        44,
                        12,
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
                  // Edit / Done icon overlay
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () {
                        setState(
                          () => _isEditingAddress = !_isEditingAddress,
                        );
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isEditingAddress
                              ? Icons.check_rounded
                              : Icons.edit_rounded,
                          size: 14,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Pin Code (auto-filled, editable) ────────────────
              _fieldLabel('Pin Code'),
              const SizedBox(height: 6),
              TextField(
                controller: _zipController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                style: const TextStyle(
                  fontSize: 14,
                  color: _ink,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 92101',
                  hintStyle: const TextStyle(
                    color: _inkSubtle,
                    fontSize: 14,
                  ),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      Icons.local_post_office_outlined,
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
              const SizedBox(height: 14),

              // ── Lat / Lon (read-only) ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      size: 15,
                      color: _inkSubtle,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_latitude!.toStringAsFixed(6)},  '
                        '${_longitude!.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _inkMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  // ── Details section ───────────────────────────────────────────────────────
  Widget _buildDetailsSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Note', Icons.edit_note_rounded),
            const SizedBox(height: 14),
            _inputField(
              controller: _noteController,
              hint: 'Add a note about this photo…',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
          ],
        ),
      );

  // ── Upload bar ────────────────────────────────────────────────────────────
  Widget _buildUploadBar(bool canUpload) => Container(
        color: _surface,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0xFFE5E7EB),
                    color: _accent,
                    minHeight: 3,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: canUpload ? _upload : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canUpload ? _accent : _separator,
                  foregroundColor: canUpload ? Colors.white : _inkSubtle,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Uploading…',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload_rounded,
                            size: 20,
                            color: canUpload ? Colors.white : _inkSubtle,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Upload Photo',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: canUpload ? Colors.white : _inkSubtle,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            // Validation dots
            if (!_isUploading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dot(_selectedImage != null),
                    const SizedBox(width: 4),
                    _dotLabel('Photo', _selectedImage != null),
                    const SizedBox(width: 14),
                    _dot(_selectedProfile != null),
                    const SizedBox(width: 4),
                    _dotLabel('Profile', _selectedProfile != null),
                    const SizedBox(width: 14),
                    _dot(_latitude != null),
                    const SizedBox(width: 4),
                    _dotLabel('Location', _latitude != null),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _dot(bool ok) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: ok ? _successGreen : _separator,
          shape: BoxShape.circle,
        ),
      );

  Widget _dotLabel(String label, bool ok) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: ok ? _successGreen : _inkSubtle,
          fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
        ),
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(
    String label,
    IconData icon, {
    bool required = false,
  }) =>
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: _accent),
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
          if (required) ...[
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
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
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

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: _errorRed,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 13, color: _errorRed),
              ),
            ),
          ],
        ),
      );
}
