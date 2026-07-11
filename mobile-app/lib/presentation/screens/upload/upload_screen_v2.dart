import 'dart:async';
import 'dart:convert';
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

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/storage/upload_queue.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/create_profile_dialog.dart';
import 'location_picker_map.dart';

enum _UploadState { idle, uploading, processing, success, failed }

class UploadScreenV2 extends ConsumerStatefulWidget {
  const UploadScreenV2({super.key});

  @override
  ConsumerState<UploadScreenV2> createState() => _UploadScreenV2State();
}

class _UploadScreenV2State extends ConsumerState<UploadScreenV2> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF7F5FF);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _accentMid = Color(0xFF8B5CF6);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFEF4444);
  static const Color _stepInactive = Color(0xFFE5E7EB);
  // Radius used to surface "Nearby" profiles first in the profile picker.
  static const double _kProfileProximityMi = 1;
  static const LinearGradient _btnGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );

  // ── Upload state enum ─────────────────────────────────────────────────────
  // idle → uploading → processing → success | failed
  _UploadState _uploadState = _UploadState.idle;
  int? _lastUploadedPhotoId;

  // ── State ─────────────────────────────────────────────────────────────────
  // Multi-photo: each entry in _selectedImages has a matching _takenAts entry.
  final List<File> _selectedImages = [];
  final List<String?> _takenAts = [];
  ProfileModel? _selectedProfile;
  double? _latitude;
  double? _longitude;
  double? _gpsAccuracy;
  bool _isLoadingLocation = false;
  bool _locationError = false;
  String? _locationErrorMsg;
  bool _isEditingAddress = false;
  String _selectedCategory = kDefaultCategory;
  // F1: when the user chooses to append to an existing pin.
  int? _locationGroupId;
  // Prevent the nearby-pin prompt from firing more than once per location.
  bool _nearbyCheckDone = false;
  // Track how many photos have been uploaded when doing a multi-upload.
  int _uploadedCount = 0;

  final _noteController = TextEditingController();
  final _addressController = TextEditingController();
  final _payRateController = TextEditingController();   // F7
  final _servedToController = TextEditingController();
  // Delivery Style — a fixed set of choices (replaces the free-text "Type").
  // Stored/sent as `completionType` to keep the backend field unchanged.
  static const List<String> _kDeliveryStyles = [
    'Personal',
    'Sub on 1st',
    'Sub on 3rd',
    'Posting',
    'Stake Out',
  ];
  String? _deliveryStyle;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Draft restore runs first so its dialog never overlaps the nearby-pin
    // dialog that _fetchLocation fires. Both use useRootNavigator:true, and
    // two concurrent root dialogs make buttons appear broken to the user.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeRestoreDraft(); // fully resolved before GPS starts
      unawaited(_fetchLocation());
    });
    // F5: auto-save the draft whenever the text fields change.
    _noteController.addListener(_saveDraft);
    _addressController.addListener(_saveDraft);
    _payRateController.addListener(_saveDraft);
    _servedToController.addListener(_saveDraft);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _addressController.dispose();
    _payRateController.dispose();
    _servedToController.dispose();
    super.dispose();
  }

  // ── F5: Draft auto-save & recovery ────────────────────────────────────────
  void _saveDraft() {
    if (_selectedImages.isEmpty && _selectedProfile == null) return;
    LocalStorage.savePinDraft(jsonEncode({
      'note': _noteController.text,
      'address': _addressController.text,
      'category': _selectedCategory,
      'payRate': _payRateController.text,
      'servedTo': _servedToController.text,
      'completionType': _deliveryStyle,
      'profileId': _selectedProfile?.id,
      'photoPaths': _selectedImages.map((f) => f.path).toList(),
      'latitude': _latitude,
      'longitude': _longitude,
      'gpsAccuracy': _gpsAccuracy,
      'takenAts': _takenAts,
      'locationGroupId': _locationGroupId,
    }));
  }

  Future<void> _maybeRestoreDraft() async {
    final raw = LocalStorage.getPinDraft();
    if (raw == null || !mounted) return;
    Map<String, dynamic> draft;
    try {
      draft = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final resume = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Resume Draft?'),
        content: const Text(
            'You have an unsaved pin in progress. Resume where you left off?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (!(resume ?? false)) {
      await LocalStorage.clearPinDraft();
      return;
    }

    // F5: restore in-progress photos (if still on disk).
    final rawPaths = draft['photoPaths'];
    final photoPaths = (rawPaths is List)
        ? rawPaths.cast<String>()
        : (draft['photoPath'] as String?) != null
            ? [draft['photoPath'] as String]
            : <String>[];
    final restoredImages =
        photoPaths.where((p) => File(p).existsSync()).map(File.new).toList();
    final rawTakenAts = draft['takenAts'];
    final restoredTakenAts = (rawTakenAts is List)
        ? rawTakenAts.cast<String?>()
        : List<String?>.filled(restoredImages.length, null);

    // F5: restore the previously-selected profile, if any.
    ProfileModel? restoredProfile;
    final profileId = draft['profileId'] as int?;
    if (profileId != null) {
      try {
        final profiles = await ref.read(profilesProvider.future);
        for (final p in profiles) {
          if (p.id == profileId) {
            restoredProfile = p;
            break;
          }
        }
      } catch (_) {/* keep going without a pre-selected profile */}
    }

    if (!mounted) return;
    setState(() {
      _noteController.text = (draft['note'] ?? '') as String;
      _addressController.text = (draft['address'] ?? '') as String;
      _payRateController.text = (draft['payRate'] ?? '') as String;
      _servedToController.text = (draft['servedTo'] ?? '') as String;
      final savedStyle = draft['completionType'] as String?;
      _deliveryStyle =
          _kDeliveryStyles.contains(savedStyle) ? savedStyle : null;
      _selectedCategory =
          (draft['category'] ?? kDefaultCategory) as String;
      _selectedImages
        ..clear()
        ..addAll(restoredImages);
      _takenAts
        ..clear()
        ..addAll(restoredTakenAts);
      _latitude = (draft['latitude'] as num?)?.toDouble();
      _longitude = (draft['longitude'] as num?)?.toDouble();
      _gpsAccuracy = (draft['gpsAccuracy'] as num?)?.toDouble();
      _locationGroupId = draft['locationGroupId'] as int?;
      if (restoredProfile != null) _selectedProfile = restoredProfile;
    });
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
          _nearbyCheckDone = false; // fresh location — re-arm the check
        });
        // F5: persist the location into the draft right away.
        _saveDraft();
        // F1: proactively check for nearby pins as soon as GPS is ready,
        // so the user is prompted before filling out the form.
        unawaited(_checkNearbyAndMaybeReuse());

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
      _nearbyCheckDone = false; // new location — re-arm the nearby check
    });
    // F5: persist the picked location into the draft right away.
    _saveDraft();
    // F1: re-run proactive nearby check for the newly picked location.
    unawaited(_checkNearbyAndMaybeReuse());

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
      // Gallery: allow picking multiple images at once.
      if (source == ImageSource.gallery) {
        // Pick at full resolution so EXIF (capture date) survives; the
        // watermark step downscales the image for upload.
        final picked = await _imagePicker.pickMultiImage();
        if (picked.isEmpty || !mounted) return;
        HapticFeedback.mediumImpact();
        final provisional = DateTime.now().toUtc().toIso8601String();
        setState(() {
          for (final x in picked) {
            _selectedImages.add(File(x.path));
            _takenAts.add(provisional);
          }
        });
        // Refine each timestamp from EXIF in the background.
        for (var i = _selectedImages.length - picked.length;
            i < _selectedImages.length;
            i++) {
          final captured = await readCaptureTimeIso(_selectedImages[i]);
          if (mounted) setState(() => _takenAts[i] = captured);
        }
        _saveDraft();
        return;
      }

      // Camera: single shot. Full resolution so EXIF survives.
      final picked = await _imagePicker.pickImage(source: source);
      if (picked != null && mounted) {
        HapticFeedback.mediumImpact();
        final provisional = DateTime.now().toUtc().toIso8601String();
        setState(() {
          _selectedImages.add(File(picked.path));
          _takenAts.add(provisional);
        });
        final captured = await readCaptureTimeIso(File(picked.path));
        if (mounted) {
          setState(() => _takenAts[_takenAts.length - 1] = captured);
        }
        _saveDraft();
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

  // Full-size preview showing the exact watermark (timestamp + address) that
  // will be baked into the photo at upload time.
  void _showPhotoPreview(int index) {
    if (index < 0 || index >= _selectedImages.length) return;
    HapticFeedback.lightImpact();
    final address = _addressController.text.trim();
    final takenAtIso = index < _takenAts.length ? _takenAts[index] : null;
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
                      child: Image.file(_selectedImages[index]),
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Close button
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
          // Caption: where this timestamp comes from
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

    if (_selectedImages.isEmpty) {
      _showSnack('Please select at least one photo', isError: true);
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

    if (_locationGroupId == null && !_nearbyCheckDone) {
      await _checkNearbyAndMaybeReuse();
      if (!mounted) return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _uploadState = _UploadState.uploading;
      _uploadedCount = 0;
    });

    final payRate = int.tryParse(_payRateController.text.trim());
    final address = _addressController.text.trim().isEmpty
        ? null
        : _addressController.text.trim();
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final servedTo = _servedToController.text.trim().isEmpty
        ? null
        : _servedToController.text.trim();
    final completionType = _deliveryStyle;

    // The watermark caption is now drawn as a live display overlay
    // (WatermarkCaption) in the feed + detail screens — from each photo's
    // metadata — and re-baked into the file only at export time. So the
    // ORIGINAL photo is uploaded/queued here; baking on upload would
    // double-stamp beneath the overlay. (Queue/geotag handling below unchanged.)
    final watermarked = List<File>.from(_selectedImages);

    // ENQUEUE-FIRST: persist every photo to the durable offline queue BEFORE
    // any network call. A signal drop, app switch, OR a hard kill mid-upload
    // all auto-resume on their own — the original EXIF timestamp + geotag
    // travel with each queued item and are never regenerated. The auto-drainer
    // is paused so it can't race the in-order upload below and double-send.
    UploadQueueService.instance.pauseAutoProcess();
    final queueIds = <String>[];
    for (var i = 0; i < watermarked.length; i++) {
      final q = await UploadQueueService.instance.enqueue(
        sourceFile: watermarked[i],
        profileId: _selectedProfile!.id,
        latitude: _latitude!,
        longitude: _longitude!,
        takenAt: _takenAts[i] ?? DateTime.now().toUtc().toIso8601String(),
        address: address,
        note: note,
        category: _selectedCategory,
        completionType: completionType,
        servedTo: servedTo,
        payRate: payRate,
        locationGroupId: _locationGroupId,
        profileName: _selectedProfile!.name,
      );
      queueIds.add(q.id);
    }

    try {
      int? lastId;
      // Group the whole batch under one master pin. If we're adding to an
      // existing pin, [_locationGroupId] is already set; otherwise the FIRST
      // uploaded photo becomes the group anchor and every following photo
      // attaches to it — so N photos make ONE profile/pin with N previews,
      // not N separate profiles.
      int? groupId = _locationGroupId;
      for (var i = 0; i < watermarked.length; i++) {
        final uploaded = await ref.read(uploadPhotoProvider({
          'filePath': watermarked[i].path,
          'profileId': _selectedProfile!.id,
          'latitude': _latitude,
          'longitude': _longitude,
          'address': address,
          'servedTo': servedTo,
          'completionType': completionType,
          'note': note,
          'category': _selectedCategory,
          'payRate': payRate,
          'takenAt': _takenAts[i],
          'locationGroupId': groupId,
        }).future);
        // Sent — drop it from the queue so the drainer can't re-send it.
        await UploadQueueService.instance.remove(queueIds[i]);
        lastId = uploaded.id;
        groupId ??= uploaded.id;
        if (mounted) setState(() => _uploadedCount = i + 1);
      }

      if (!mounted) return;
      await LocalStorage.clearPinDraft();
      HapticFeedback.heavyImpact();
      setState(() {
        _uploadState = _UploadState.success;
        _lastUploadedPhotoId = lastId;
      });
      final n = _selectedImages.length;
      _showSnack(_locationGroupId != null
          ? 'Added to existing pin ($n photo${n > 1 ? 's' : ''})'
          : 'Uploaded $n photo${n > 1 ? 's' : ''} successfully');
    } catch (e) {
      debugPrint('[UPLOAD ERROR] $e');
      if (!mounted) return;
      // Field signal dropped (or the server is unreachable). The un-sent photos
      // are already safe in the offline queue (enqueued above) and will upload
      // automatically when connectivity returns — nothing more to persist.
      final queued = watermarked.length - _uploadedCount;
      await LocalStorage.clearPinDraft();
      HapticFeedback.heavyImpact();
      setState(() {
        _uploadState = _UploadState.success;
      });
      _showSnack(
        'Saved offline — $queued photo${queued > 1 ? 's' : ''} will upload '
        'automatically when you have signal.',
      );
    } finally {
      UploadQueueService.instance.resumeAutoProcess();
    }
  }

  // ── F1: nearby duplicate detection + existing-pin reuse ───────────────────
  Future<void> _checkNearbyAndMaybeReuse() async {
    if (_nearbyCheckDone || _latitude == null || _longitude == null) return;
    try {
      final nearby = await ref.read(apiServiceProvider).getNearby(
            latitude: _latitude!,
            longitude: _longitude!,
            radiusFt: 5280, // searchable/reusable profiles: 1 mile
          );
      if (nearby.isEmpty || !mounted) return;
      final nearest = nearby.first;
      final distFt = (nearest['distance_ft'] as num?)?.toDouble();
      // Friendlier distance now that the search radius is 1 mile.
      final dist = distFt == null
          ? '?'
          : distFt >= 1000
              ? '${(distFt / 5280).toStringAsFixed(1)} mi'
              : '${distFt.toStringAsFixed(0)} ft';
      final count = nearest['attempt_count'] ?? 0;
      final useExisting = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Nearby pin found'),
          content: Text(
              'A pin exists ~$dist away with $count logged attempt(s).\n\n'
              'Add your photo, timestamp and note to that pin, or start a new one?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('New Pin'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Add to Existing'),
            ),
          ],
        ),
      );
      if ((useExisting ?? false) && mounted) {
        setState(() =>
            _locationGroupId = nearest['location_group_id'] as int?);
        _saveDraft();
      }
    } catch (_) {
      // Best-effort — never block an upload on this.
    } finally {
      if (mounted) setState(() => _nearbyCheckDone = true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final canUpload = _selectedImages.isNotEmpty &&
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
                  _buildCategorySection(),
                  const SizedBox(height: 14),
                  _buildDeliveryStyleSection(),
                  const SizedBox(height: 14),
                  _buildLocationSection(),
                  const SizedBox(height: 14),
                  _buildDetailsSection(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _buildStickyFooter(canUpload),
        ],
      ),
    );
  }

  // ── Sticky footer CTA ────────────────────────────────────────────────────
  Widget _buildStickyFooter(bool canUpload) {
    final isActive = _uploadState != _UploadState.idle;
    final isInProgress = _uploadState == _UploadState.uploading ||
        _uploadState == _UploadState.processing;

    String label;
    IconData btnIcon;
    Color? overrideColor;

    switch (_uploadState) {
      case _UploadState.uploading:
        final total = _selectedImages.length;
        label = total > 1
            ? 'Uploading ${_uploadedCount + 1} of $total…'
            : 'Uploading photo…';
        btnIcon = Icons.cloud_upload_outlined;
        break;
      case _UploadState.processing:
        label = 'Processing…';
        btnIcon = Icons.cloud_upload_outlined;
        break;
      case _UploadState.success:
        label = 'Upload Complete';
        btnIcon = Icons.check_circle_rounded;
        overrideColor = _successGreen;
        break;
      case _UploadState.failed:
        label = 'Failed — Tap to Retry';
        btnIcon = Icons.refresh_rounded;
        overrideColor = _errorRed;
        break;
      case _UploadState.idle:
        label = canUpload ? 'Upload Photo' : _missingFieldsHint();
        btnIcon = Icons.cloud_upload_outlined;
    }

    final bool tappable =
        (canUpload && _uploadState == _UploadState.idle) ||
            _uploadState == _UploadState.failed;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(
          top: BorderSide(color: _separator, width: 1),
        ),
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
          // ── Success: View Post + Done ───────────────────────────────────
          if (_uploadState == _UploadState.success) ...[
            Row(
              children: [
                if (_lastUploadedPhotoId != null)
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            context.push('/photo/$_lastUploadedPhotoId'),
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
                if (_lastUploadedPhotoId != null) const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/home'),
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
          ] else
          SizedBox(
            width: double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: overrideColor == null && (canUpload || isActive)
                    ? _btnGradient
                    : null,
                color: overrideColor ??
                    (!canUpload && !isActive
                        ? const Color(0xFFE5E7EB)
                        : null),
                borderRadius: BorderRadius.circular(18),
                boxShadow: tappable || isActive
                    ? [
                        BoxShadow(
                          color: (overrideColor ?? _accent)
                              .withValues(alpha: 0.38),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: tappable ? _upload : null,
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
                      Icon(btnIcon, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: (!canUpload && !isActive)
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

  // ── Header (step-based progress) ──────────────────────────────────────────
  Widget _buildHeader() {
    final items = <(String, bool)>[
      ('Photo', _selectedImages.isNotEmpty),
      ('Profile', _selectedProfile != null),
      ('Location', _latitude != null && !_isLoadingLocation),
    ];
    final done = items.where((t) => t.$2).length;
    final allDone = done == 3;

    return Container(
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
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    color: _inkMuted,
                    onPressed: context.pop,
                  ),
                  const Expanded(
                    child: Text(
                      'New Upload',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (allDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _successGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Ready!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _successGreen,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: items[i].$2
                                  ? _successGreen
                                  : i == done
                                      ? _accent
                                      : _stepInactive,
                              shape: BoxShape.circle,
                              boxShadow: items[i].$2 || i == done
                                  ? [
                                      BoxShadow(
                                        color: (items[i].$2
                                                ? _successGreen
                                                : _accent)
                                            .withValues(alpha: 0.32),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: items[i].$2
                                  ? const Icon(Icons.check_rounded,
                                      size: 18, color: Colors.white)
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: i == done
                                            ? Colors.white
                                            : _inkSubtle,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            items[i].$1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: items[i].$2
                                  ? _successGreen
                                  : i == done
                                      ? _accent
                                      : _inkSubtle,
                            ),
                          ),
                        ],
                      ),
                      if (i < items.length - 1)
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 2,
                            margin: const EdgeInsets.only(bottom: 22),
                            decoration: BoxDecoration(
                              gradient: items[i].$2
                                  ? LinearGradient(colors: [
                                      _successGreen,
                                      _successGreen.withValues(alpha: 0.4),
                                    ])
                                  : null,
                              color: items[i].$2 ? null : _stepInactive,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo section (multi-photo) ──────────────────────────────────────────
  Widget _buildPhotoSection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Photos',
              Icons.camera_alt_rounded,
              required: true,
              done: _selectedImages.isNotEmpty,
            ),
            if (_selectedImages.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${_selectedImages.length} photo'
                '${_selectedImages.length > 1 ? 's' : ''} selected'
                ' · tap to preview the timestamp',
                style: const TextStyle(fontSize: 12, color: _inkSubtle),
              ),
            ],
            const SizedBox(height: 12),
            // Thumbnail strip — shown when at least one photo is selected.
            // Each thumbnail carries a live timestamp watermark identical to
            // the one baked in at upload; tap to see the full-size preview.
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _showPhotoPreview(i),
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
                                    _selectedImages[i],
                                    fit: BoxFit.cover,
                                    // Full-res source; decode small for the
                                    // thumbnail to keep memory low.
                                    cacheWidth: 320,
                                  ),
                                  // Live timestamp watermark (compact)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: WatermarkBar(
                                      takenAtIso: i < _takenAts.length
                                          ? _takenAts[i]
                                          : null,
                                      compact: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedImages.removeAt(i);
                                if (i < _takenAts.length) {
                                  _takenAts.removeAt(i);
                                }
                                _saveDraft();
                              }),
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
                          // Index badge
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
            // Prominent, always-visible capture-time field while building.
            if (_selectedImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              _captureTimeCard(),
            ],
            if (_selectedImages.isEmpty)
              GestureDetector(
                onTap: () => _pickImage(ImageSource.camera),
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

  // Always-visible timestamp field: shows the photo's capture time (EXIF) the
  // moment a photo is added — this is exactly what gets baked into the
  // watermark on upload.
  Widget _captureTimeCard() {
    final iso = _takenAts.isNotEmpty ? _takenAts.first : null;
    final label = iso == null ? 'Reading photo time…' : formatStamp(iso);
    final multi = _selectedImages.length > 1;
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
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: _canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _accent.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded,
                              color: _accent, size: 22),
                        ),
                        const SizedBox(height: 10),
                        const Text('No profiles yet',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _ink)),
                        const SizedBox(height: 4),
                        const Text('Add a profile to attach this upload to.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 12.5, color: _inkMuted)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showCreateProfileDialog,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
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
  // ── Delivery Style ────────────────────────────────────────────────────────
  // Replaces the old free-text "Type" field with a fixed dropdown. The value is
  // sent to the backend as `completionType` (unchanged wire format).
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
                  value: _deliveryStyle,
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
                  items: _kDeliveryStyles
                      .map((s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s,
                                style: const TextStyle(
                                    fontSize: 14, color: _ink)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    setState(() => _deliveryStyle = value);
                    _saveDraft();
                  },
                ),
              ),
            ),
          ],
        ),
      );

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
                    _saveDraft();
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

  // Profile IDs with a photo within _kProfileProximityMi of the current
  // upload location — surfaced first in the picker so the right profile is
  // easy to find without scrolling/searching a long roster.
  Set<int> _nearbyProfileIds() {
    if (_latitude == null || _longitude == null) return {};
    final photos = ref.read(photosProvider).valueOrNull ?? const [];
    final ids = <int>{};
    for (final p in photos) {
      if (p.profileId == null) continue;
      final km = LocationService.calculateDistance(
          _latitude!, _longitude!, p.latitude, p.longitude);
      if (km * 0.621371 <= _kProfileProximityMi) ids.add(p.profileId!);
    }
    return ids;
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
    final sel = _selectedProfile?.id == p.id;
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

  void _showProfilePicker(List<ProfileModel> profiles) {
    HapticFeedback.lightImpact();
    final searchCtrl = TextEditingController();
    final nearbyIds = _nearbyProfileIds();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? profiles
              : profiles
                  .where((p) => p.name.toLowerCase().contains(query))
                  .toList();
          final nearby =
              filtered.where((p) => nearbyIds.contains(p.id)).toList();
          final others =
              filtered.where((p) => !nearbyIds.contains(p.id)).toList();

          void select(ProfileModel p) {
            HapticFeedback.selectionClick();
            setState(() => _selectedProfile = p);
            _saveDraft();
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
                // ── Search ────────────────────────────────────────────────
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
                // ── New profile shortcut ─────────────────────────────────────
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
                            'Nearby · within $_kProfileProximityMi mi'),
                        ...nearby.map((p) => _profilePickerTile(
                              p,
                              nearby: true,
                              onSelect: () => select(p),
                            )),
                        if (others.isNotEmpty) const SizedBox(height: 10),
                      ],
                      if (others.isNotEmpty) ...[
                        if (nearby.isNotEmpty)
                          _pickerSectionLabel('All profiles'),
                        ...others.map((p) => _profilePickerTile(
                              p,
                              nearby: false,
                              onSelect: () => select(p),
                            )),
                      ],
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No profiles match "${searchCtrl.text.trim()}"',
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

  // ── Profile creation (shared dialog) ──────────────────────────────────────
  Future<void> _showCreateProfileDialog() async {
    final created = await showCreateProfileDialog(context);
    if (created != null && mounted) {
      setState(() => _selectedProfile = created);
      _saveDraft();
      _showSnack('Profile "${created.name}" created');
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
                          Icons.location_on_outlined,
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
                      Icons.location_off_outlined,
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
                    textCapitalization: TextCapitalization.words,
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
                          Icons.apartment_rounded,
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
                              : Icons.edit_outlined,
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
                      Icons.location_on_rounded,
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
            _sectionLabel('Note', Icons.edit_outlined),
            const SizedBox(height: 14),
            _inputField(
              controller: _noteController,
              hint: 'Add a note about this photo…',
              icon: Icons.description_outlined,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: const [SentenceCaseInputFormatter()],
            ),
            const SizedBox(height: 16),
            // Completion detail — Served To
            _fieldLabel('Served To', optional: true),
            const SizedBox(height: 6),
            _inputField(
              controller: _servedToController,
              hint: 'Name of person served',
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseInputFormatter()],
            ),
            const SizedBox(height: 16),
            // F7 — Pay rate
            _fieldLabel('Pay Rate (\$)', optional: true),
            const SizedBox(height: 6),
            _inputField(
              controller: _payRateController,
              hint: 'e.g. 30',
              icon: Icons.attach_money,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      );

  /// Returns a hint about what's still needed.
  String _missingFieldsHint() {
    final missing = <String>[];
    if (_selectedImages.isEmpty) missing.add('photo');
    if (_selectedProfile == null) missing.add('profile');
    if (_latitude == null && !_isLoadingLocation) missing.add('location');
    if (_isLoadingLocation) return 'Waiting for GPS…';
    if (missing.isEmpty) return '';
    return 'Still needed: ${missing.join(', ')}';
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
                      colors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
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
