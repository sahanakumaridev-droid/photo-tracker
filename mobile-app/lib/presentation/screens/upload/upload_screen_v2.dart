import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import 'location_picker_map.dart';

enum _UploadState { idle, uploading, processing, success, failed }

class UploadScreenV2 extends ConsumerStatefulWidget {
  const UploadScreenV2({super.key});

  @override
  ConsumerState<UploadScreenV2> createState() => _UploadScreenV2State();
}

class _UploadScreenV2State extends ConsumerState<UploadScreenV2> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFFAFAFA);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFEF4444);

  // ── Upload state enum ─────────────────────────────────────────────────────
  // idle → uploading → processing → success | failed
  _UploadState _uploadState = _UploadState.idle;

  // ── State ─────────────────────────────────────────────────────────────────
  File? _selectedImage;
  ProfileModel? _selectedProfile;
  double? _latitude;
  double? _longitude;
  double? _gpsAccuracy;
  bool _isLoadingLocation = false;
  bool _locationError = false;
  String? _locationErrorMsg;
  bool _isEditingAddress = false;
  String _selectedCategory = kDefaultCategory;

  final _noteController = TextEditingController();
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
    _addressController.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = false;
      _locationErrorMsg = null;
      _addressController.clear();
    });
    try {
      // 1. Check permission
      final granted = await LocationService.requestLocationPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _locationError = true;
            _locationErrorMsg =
                'Location permission denied. Please enable it in Settings.';
          });
        }
        return;
      }

      // 2. Check service enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationError = true;
            _locationErrorMsg =
                'Location services are off. Please enable GPS in Settings.';
          });
        }
        return;
      }

      // 3. Fast first paint — use last-known position
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _latitude = last.latitude;
            _longitude = last.longitude;
            _gpsAccuracy = last.accuracy;
          });
        }
      } catch (_) {}

      // 4. Fetch fresh high-accuracy fix (with retry in LocationService)
      final freshPos = await LocationService.getCurrentLocation();
      if (freshPos == null) {
        if (mounted) {
          setState(() {
            _locationError = _latitude == null;
            _locationErrorMsg = _latitude == null
                ? 'Could not get your location. Tap Refresh to try again.'
                : null;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _latitude = freshPos.latitude;
          _longitude = freshPos.longitude;
          _gpsAccuracy = freshPos.accuracy;
          _locationError = false;
          _locationErrorMsg = null;
        });

        // Reverse geocode for address (ZIP is inline in the address string)
        final address = await LocationService.reverseGeocode(
          freshPos.latitude,
          freshPos.longitude,
        );
        if (mounted && address != null && address.isNotEmpty) {
          setState(() {
            _addressController.text = address;
          });
        }
      }
    } catch (e) {
      debugPrint('[Upload] location error: $e');
      if (mounted) {
        setState(() {
          _locationError = _latitude == null;
          _locationErrorMsg = _latitude == null
              ? 'Location unavailable. Tap Refresh to try again.'
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Map picker ────────────────────────────────────────────────────────────
  Future<void> _openMapPicker() async {
    final initial = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : null;

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerMap(initial: initial),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _latitude = picked.latLng.latitude;
      _longitude = picked.latLng.longitude;
      _locationError = false;
    });

    // Prefer the address the picker already resolved (matches the pin exactly);
    // only reverse-geocode as a fallback if it didn't have one.
    if (picked.address != null && picked.address!.isNotEmpty) {
      setState(() {
        _addressController.text = picked.address!;
        _isLoadingLocation = false;
      });
      return;
    }
    setState(() => _isLoadingLocation = true);
    try {
      final address = await LocationService.reverseGeocode(
        picked.latLng.latitude,
        picked.latLng.longitude,
      );
      if (mounted && address != null && address.isNotEmpty) {
        setState(() => _addressController.text = address);
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
    // Guard: prevent duplicate submissions
    if (_uploadState == _UploadState.uploading ||
        _uploadState == _UploadState.processing) {
      return;
    }

    if (_selectedImage == null) {
      _showSnack('Please select a photo first', isError: true);
      return;
    }
    if (_selectedProfile == null) {
      _showSnack('Please select a profile', isError: true);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showSnack('Location required. Tap Refresh to retry.', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _uploadState = _UploadState.uploading);

    try {
      await ref.read(uploadPhotoProvider({
        'filePath': _selectedImage!.path,
        'profileId': _selectedProfile!.id,
        'latitude': _latitude,
        'longitude': _longitude,
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        'category': _selectedCategory,
      }).future);

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _uploadState = _UploadState.success);
      _showSnack('Photo uploaded successfully');
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (mounted) context.go('/home');
    } catch (e) {
      debugPrint('[UPLOAD ERROR] $e');
      if (!mounted) return;
      setState(() => _uploadState = _UploadState.failed);
      _showSnack(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (mounted) setState(() => _uploadState = _UploadState.idle);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final canUpload = _selectedImage != null &&
        _selectedProfile != null &&
        _latitude != null &&
        _uploadState == _UploadState.idle;

    return Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPhotoSection(),
                  const SizedBox(height: 14),
                  _buildProfileSection(profilesAsync),
                  const SizedBox(height: 14),
                  _buildLocationSection(),
                  const SizedBox(height: 14),
                  _buildCategorySection(),
                  const SizedBox(height: 14),
                  _buildDetailsSection(),
                  const SizedBox(height: 20),
                  _buildUploadBar(canUpload),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header (with required-step progress) ────────────────────────────────────
  Widget _buildHeader() {
    final done = [
      _selectedImage != null,
      _selectedProfile != null,
      _latitude != null && !_isLoadingLocation,
    ].where((x) => x).length;
    final ready = done == 3;
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _separator)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: _inkMuted,
                    onPressed: context.pop,
                  ),
                  const Expanded(
                    child: Text(
                      'New Capture',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (ready ? _successGreen : _accent)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$done/3',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: ready ? _successGreen : _accent)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: done / 3,
                    minHeight: 6,
                    backgroundColor: _separator,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        ready ? _successGreen : _accent),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  ready
                      ? 'All set — ready to upload'
                      : 'Add a photo, profile and location to continue',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: ready ? _successGreen : _inkSubtle,
                      fontWeight:
                          ready ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo section ─────────────────────────────────────────────────────────
  Widget _buildPhotoSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Photo', Icons.camera_alt_rounded,
                required: true, done: _selectedImage != null),
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
              done: _selectedProfile != null,
            ),
            const SizedBox(height: 12),
            profilesAsync.when(
              loading: () => _shimmerBox(height: 56, radius: 12),
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

  // ── Category section ──────────────────────────────────────────────────────
  Widget _buildCategorySection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Category',
              Icons.label_rounded,
              done: true,
            ),
            const SizedBox(height: 6),
            const Text(
              'Tag this photo with a priority level.',
              style: TextStyle(fontSize: 13, color: _inkSubtle),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kPhotoCategories.map((c) {
                final selected = _selectedCategory == c.value;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = c.value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 112,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? c.color : c.softColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? c.color
                            : c.color.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          c.icon,
                          size: 16,
                          color: selected ? Colors.white : c.color,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 14,
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
                    done: _latitude != null && !_isLoadingLocation,
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

            // ── Loading (shimmer) ────────────────────────────────────
            if (_isLoadingLocation)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent),
                      ),
                      SizedBox(width: 10),
                      Text('Fetching current location…',
                          style: TextStyle(fontSize: 13, color: _inkMuted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _shimmerBox(height: 48, radius: 12),
                  const SizedBox(height: 8),
                  _shimmerBox(height: 44, radius: 12),
                  const SizedBox(height: 8),
                  _shimmerBox(height: 40, radius: 12),
                ],
              )

            // ── Error ────────────────────────────────────────────────
            else if (_locationError || _latitude == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_off_rounded,
                      size: 18,
                      color: _errorRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationErrorMsg ??
                            'Location unavailable. Tap Refresh to retry.',
                        style: const TextStyle(fontSize: 13, color: _errorRed),
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
                    Icon(
                      Icons.gps_fixed_rounded,
                      size: 15,
                      color: (_gpsAccuracy != null && _gpsAccuracy! > 50)
                          ? Colors.orange
                          : _inkSubtle,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_latitude!.toStringAsFixed(6)},  '
                            '${_longitude!.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _inkMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (_gpsAccuracy != null)
                            Text(
                              'Accuracy: ±${_gpsAccuracy!.toStringAsFixed(0)}m'
                              '${_gpsAccuracy! > 50 ? ' (low — tap Refresh)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: _gpsAccuracy! > 50
                                    ? Colors.orange
                                    : _inkSubtle,
                              ),
                            ),
                        ],
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
  Widget _buildUploadBar(bool canUpload) {
    final isActive = _uploadState != _UploadState.idle;

    String label;
    Color btnColor;
    IconData btnIcon;

    switch (_uploadState) {
      case _UploadState.uploading:
        label = 'Uploading photo…';
        btnColor = _accent;
        btnIcon = Icons.cloud_upload_rounded;
        break;
      case _UploadState.processing:
        label = 'Processing…';
        btnColor = _accent;
        btnIcon = Icons.cloud_upload_rounded;
        break;
      case _UploadState.success:
        label = 'Upload Complete ✓';
        btnColor = _successGreen;
        btnIcon = Icons.check_circle_rounded;
        break;
      case _UploadState.failed:
        label = 'Failed — Tap to Retry';
        btnColor = _errorRed;
        btnIcon = Icons.refresh_rounded;
        break;
      case _UploadState.idle:
        label = 'Upload Photo';
        btnColor = canUpload ? _accent : const Color(0xFFD1D5DB);
        btnIcon = Icons.cloud_upload_rounded;
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // (Step progress now lives in the header; the bar stays clean.)
          // ── Progress bar during upload ────────────────────────────────
          if (_uploadState == _UploadState.uploading ||
              _uploadState == _UploadState.processing) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: _accent.withValues(alpha: 0.15),
                color: _accent,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Main button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              child: ElevatedButton(
                onPressed: canUpload && _uploadState == _UploadState.idle
                    ? _upload
                    : _uploadState == _UploadState.failed
                        ? _upload
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD1D5DB),
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  elevation: canUpload ? 2 : 0,
                  shadowColor: _accent.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isActive &&
                        _uploadState != _UploadState.success &&
                        _uploadState != _UploadState.failed)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(btnIcon, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Helper text when button is disabled ───────────────────────
          if (_uploadState == _UploadState.idle && !canUpload) ...[
            const SizedBox(height: 8),
            Text(
              _missingFieldsHint(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns a hint about what's still needed.
  String _missingFieldsHint() {
    final missing = <String>[];
    if (_selectedImage == null) missing.add('photo');
    if (_selectedProfile == null) missing.add('profile');
    if (_latitude == null && !_isLoadingLocation) missing.add('location');
    if (_isLoadingLocation) return 'Waiting for GPS…';
    if (missing.isEmpty) return '';
    return 'Still needed: ${missing.join(', ')}';
  }

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
    bool done = false,
  }) =>
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done ? _successGreen : _accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(done ? Icons.check_rounded : icon,
                size: 15, color: done ? Colors.white : _accent),
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
            const Text('Done',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _successGreen)),
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

  /// Shimmer placeholder — used while loading profiles or location.
  Widget _shimmerBox({required double height, double radius = 8}) =>
      Shimmer.fromColors(
        baseColor: const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}
