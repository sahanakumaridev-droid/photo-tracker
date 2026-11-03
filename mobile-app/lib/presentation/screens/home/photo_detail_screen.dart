import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/profile_lifecycle.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../core/utils/maps_launcher.dart';
import '../../../data/models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../upload/attempt_limits.dart';
import '../upload/resume_attempt_screen.dart';
import '../../widgets/ai/note_suggestion_chips.dart';
import '../../widgets/ai/voice_mic_button.dart';

part 'photo_detail_export.dart';
part 'photo_detail_scaffold.dart';
part 'photo_detail_status_and_location.dart';
part 'photo_detail_edit_sheet.dart';

class PhotoDetailScreen extends ConsumerStatefulWidget {
  const PhotoDetailScreen({required this.photoId, super.key});

  final int photoId;

  @override
  ConsumerState<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

// ── Design tokens (matches HomeScreenV2) ───────────────────────────────────
const Color _canvas = Color(0xFFF2F4F7);
const Color _surface = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF1A2130);
const Color _inkMuted = Color(0xFF5C6778);
const Color _inkSubtle = Color(0xFF8B95A5);
const Color _separator = Color(0xFFE3E7EE);
const Color _accent = Color(0xFF4A90E2);
const Color _accentSoft = Color(0x1F4A90E2);
const Color _rushRed = Color(0xFFDC2626);
const Color _standardGreen = Color(0xFF10B981);
const Color _airportBlue = Color(0xFF0284C7);

const _statusSteps = [
  kProfilePending,
  kProfileInProgress,
  kProfileCompleted,
  kProfileArchived,
];

class _PhotoDetailScreenState extends ConsumerState<PhotoDetailScreen> {
  bool _imageExpanded = false;

  // ── Live reverse-geocoded address (for photos that only have ZIP stored) ──
  String? _resolvedAddress;
  bool _resolvingAddress = false;

  /// Called once when the photo loads — if address is missing, fetch it live
  /// from the photo's stored lat/lng via Nominatim.
  Future<void> _resolveAddressIfNeeded(PhotoModel photo) async {
    final hasAddress = photo.address != null && photo.address!.isNotEmpty;
    if (hasAddress) return; // already stored — nothing to do

    if (_resolvingAddress) return;
    if (!mounted) return;

    setState(() => _resolvingAddress = true);
    try {
      final address = await LocationService.reverseGeocode(
        photo.latitude,
        photo.longitude,
      );
      if (mounted && address != null && address.isNotEmpty) {
        setState(() => _resolvedAddress = address);
      }
    } catch (_) {
      // Silently fail — fallback to ZIP shown below
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  // ── Edit state ────────────────────────────────────────────────────────────

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _svcColor(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return _rushRed;
      case 'airport':
        return _airportBlue;
      default:
        return _standardGreen;
    }
  }

  // ── F10: job lifecycle status ─────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'completed':
        return _standardGreen;
      case 'archived':
        return const Color(0xFF6B7280);
      default:
        return _airportBlue;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'in_progress':
        return Icons.sync_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      case 'archived':
        return Icons.inventory_2_rounded;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'archived':
        return 'Archived';
      default:
        return 'Pending';
    }
  }

  Future<void> _archiveFromDetail(ProfileModel profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this profile?'),
        content: const Text(
          'Use archive after you have independently verified payment. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(setProfileStatusProvider((
        profileId: profile.id,
        status: kProfileArchived,
      )).future);
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile archived')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _setStatus(PhotoModel photo, String status) async {
    final current = photo.status ?? 'open';
    if (status == current) return;
    HapticFeedback.mediumImpact();

    // Confirm every status change — forward OR backward — so an accidental
    // tap can't silently move a job (e.g. straight to Completed).
    final confirmed = await _confirmStatusChange(current, status);
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(updateStatusProvider((photo.id, status)).future);
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Status updated to ${_statusLabel(status)}'),
              backgroundColor: _statusColor(status),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              // One-tap revert to the prior status (no extra confirm).
              action: SnackBarAction(
                label: 'Undo',
                textColor: Colors.white,
                onPressed: () => _revertStatus(photo.id, current),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ));
      }
    }
  }

  /// Explicit undo from the snackbar — reverts straight to [previous] without
  /// re-confirming, since the user has just chosen to undo.
  Future<void> _revertStatus(int photoId, String previous) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(updateStatusProvider((photoId, previous)).future);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Reverted to ${_statusLabel(previous)}'),
              backgroundColor: _statusColor(previous),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ));
      }
    }
  }

  /// "Are you sure?" confirmation shown before any status change. Names both
  /// the old and the new status and whether it's moving forward or back.
  Future<bool?> _confirmStatusChange(String from, String to) {
    final fromIdx = _statusSteps.indexOf(from);
    final toIdx = _statusSteps.indexOf(to);
    final goingBack = toIdx >= 0 && fromIdx >= 0 && toIdx < fromIdx;
    final toColor = _statusColor(to);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              goingBack ? Icons.undo_rounded : _statusIcon(to),
              color: toColor,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(goingBack ? 'Revert status?' : 'Change status?',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are changing this job from',
                style: TextStyle(fontSize: 14, color: _inkSubtle)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statusPill(from),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: _inkSubtle),
                ),
                _statusPill(to),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: toColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _statusColor(status).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _statusColor(status),
          ),
        ),
      );

  // ── Single-attempt export: email with logged data + stamped photo ─────────
  // Tap emails saved recipients. Long-press opens the share sheet with the
  // watermarked photo and a text summary — never an Excel spreadsheet.
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  PhotoModel? _findPhoto(List<PhotoModel> photos) {
    final id = _viewingPhotoId ?? widget.photoId;
    final matches = photos.where((p) => p.id == id);
    if (matches.isNotEmpty) return matches.first;
    final fallback = photos.where((p) => p.id == widget.photoId);
    return fallback.isEmpty ? null : fallback.first;
  }

  int? _viewingPhotoId;
  /// Index into newest-first attempt groups. 0 is the latest attempt.
  int _shownAttempt = 0;
  PageController? _photoPageCtrl;
  PageController? _attemptPageCtrl;
  int _photoCtrlAttemptKey = -999;
  bool _startingNewAttempt = false;
  bool _attemptPagerReady = false;

  String _photoTime(PhotoModel p) =>
      (p.takenAt ?? p.timestamp ?? p.createdAt ?? '').trim();

  int _attemptGroupKey(PhotoModel p) {
    if (p.attemptId != null && p.attemptId != 0) return p.attemptId!;
    // location_group_id falls back to photo id on the API — that is not a
    // real group, so don't treat it as one.
    if (p.locationGroupId != null &&
        p.locationGroupId != 0 &&
        p.locationGroupId != p.id) {
      return p.locationGroupId!;
    }
    return p.id;
  }

  bool _isUngroupedShot(PhotoModel p) {
    final hasAttempt = p.attemptId != null && p.attemptId != 0;
    final hasRealGroup = p.locationGroupId != null &&
        p.locationGroupId != 0 &&
        p.locationGroupId != p.id;
    return !hasAttempt && !hasRealGroup;
  }

  DateTime? _photoDate(PhotoModel p) {
    final raw = _photoTime(p);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<List<PhotoModel>> _attemptGroups(
      PhotoModel current, List<PhotoModel> all) {
    final pid = current.profileId;
    var pool = pid == null
        ? <PhotoModel>[current]
        : all.where((p) => p.profileId == pid).toList();
    if (pool.isEmpty) pool = [current];
    final map = <int, List<PhotoModel>>{};
    for (final p in pool) {
      map.putIfAbsent(_attemptGroupKey(p), () => []).add(p);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final byTime = _photoTime(b).compareTo(_photoTime(a));
        if (byTime != 0) return byTime;
        return b.id.compareTo(a.id);
      });
    }

    final linked = <List<PhotoModel>>[];
    final lonelies = <PhotoModel>[];
    for (final list in map.values) {
      if (list.length == 1 && _isUngroupedShot(list.first)) {
        lonelies.add(list.first);
      } else {
        linked.add(list);
      }
    }
    lonelies.sort((a, b) {
      final byTime = _photoTime(b).compareTo(_photoTime(a));
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
    final clustered = <List<PhotoModel>>[];
    for (final p in lonelies) {
      if (clustered.isEmpty) {
        clustered.add([p]);
        continue;
      }
      final cluster = clustered.last;
      final head = _photoDate(cluster.first);
      final next = _photoDate(p);
      final sameWindow = head != null &&
          next != null &&
          head.difference(next).abs() <= const Duration(minutes: 45);
      if (sameWindow) {
        cluster.add(p);
      } else {
        clustered.add([p]);
      }
    }

    final groups = [...linked, ...clustered];
    for (final list in groups) {
      list.sort((a, b) {
        final byTime = _photoTime(b).compareTo(_photoTime(a));
        if (byTime != 0) return byTime;
        return b.id.compareTo(a.id);
      });
    }
    DateTime when(List<PhotoModel> g) {
      DateTime? best;
      for (final p in g) {
        final d = _photoDate(p);
        if (d == null) continue;
        if (best == null || d.isAfter(best)) best = d;
      }
      return best ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    // Newest attempt first so it is the card on top. Number is n, n-1, … 1.
    groups.sort((a, b) {
      final byTime = when(b).compareTo(when(a));
      if (byTime != 0) return byTime;
      return b.first.id.compareTo(a.first.id);
    });
    return groups;
  }

  // ── Edit actions ──────────────────────────────────────────────────────────

  void _showEditSheet(PhotoModel photo) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditPhotoSheet(photo: photo, parentRef: ref),
    );
  }

  // ── Map / clipboard actions ───────────────────────────────────────────────
  Future<void> _openInMaps(PhotoModel photo) async {
    // Prefer the human-readable address (behaves like pasting it into Maps);
    // fall back to coordinates when no address is available.
    final address = photo.address ?? _resolvedAddress;
    final launched = await MapsLauncher.openLocation(
      address: address,
      lat: photo.latitude,
      lng: photo.longitude,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open Maps'),
          backgroundColor: _accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _copyCoords(double lat, double lng) {
    Clipboard.setData(ClipboardData(text: '$lat, $lng'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coordinates copied to clipboard'),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _photoPageCtrl?.dispose();
    _attemptPageCtrl?.dispose();
    super.dispose();
  }

  void _ensureSwipeControllers({
    required int attemptPage,
    required int photoIdx,
    required int attemptIdx,
  }) {
    _attemptPageCtrl ??= PageController(initialPage: attemptPage);
    if (_photoPageCtrl == null || _photoCtrlAttemptKey != attemptIdx) {
      final old = _photoPageCtrl;
      _photoPageCtrl = PageController(initialPage: photoIdx);
      _photoCtrlAttemptKey = attemptIdx;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
  }

  Future<void> _openNewAttempt(PhotoModel photo) async {
    if (_startingNewAttempt) return;
    final pid = photo.profileId ??
        ((photo.profiles?.isNotEmpty ?? false) ? photo.profiles!.first.id : null);
    if (pid == null || pid == 0) return;
    _startingNewAttempt = true;
    HapticFeedback.mediumImpact();
    try {
      ProfileModel? profile;
      for (final p in ref.read(profilesProvider).valueOrNull ?? const []) {
        if (p.id == pid) {
          profile = p;
          break;
        }
      }
      final points = <(double, double)>[
        if (photo.latitude != 0 || photo.longitude != 0)
          (photo.latitude, photo.longitude),
        if (profile != null && profile.hasLocation)
          (profile.latitude!, profile.longitude!),
      ];
      if (points.isNotEmpty) {
        final gps = await LocationService.getFreshFix();
        if (!mounted) return;
        double? feet;
        if (gps != null) {
          for (final pt in points) {
            final d = LocationService.distanceFeet(
                gps.latitude, gps.longitude, pt.$1, pt.$2);
            if (feet == null || d < feet) feet = d;
          }
        }
        if (feet == null || feet > LocationService.kAttemptProximityFt) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Move closer'),
              content: Text(
                feet == null
                    ? 'Turn on location. An attempt can only be added within 500 feet of this profile.'
                    : 'You are ${feet.round()} ft away. Get within 500 feet of this profile to add an attempt.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }
      final ok = await ensureCanStartNewAttempt(
        context,
        ref,
        profileId: pid,
        knownCount: null,
      );
      if (!ok || !mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ResumeAttemptScreen(
            initialProfileId: pid,
            initialProfile: profile,
          ),
        ),
      );
      if (mounted) refreshProfileWork(ref, profileId: pid);
    } finally {
      _startingNewAttempt = false;
      if (mounted && _attemptPageCtrl != null && _attemptPageCtrl!.hasClients) {
        _attemptPageCtrl!.jumpToPage(1);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);

    return photosAsync.when(
      loading: _buildLoadingScaffold,
      error: _buildErrorScaffold,
      data: (photos) {
        final photo = _findPhoto(photos);
        if (photo == null) {
          return _buildNotFoundScaffold();
        }
        // Auto reverse-geocode if address is missing
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resolveAddressIfNeeded(photo),
        );
        return _buildDetailScaffold(photo, photos);
      },
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoadingScaffold() => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildErrorScaffold(Object err, StackTrace _) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _rushRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 32,
                    color: _rushRed,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString().replaceAll('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: _inkSubtle),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(photosProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Not found ─────────────────────────────────────────────────────────────
  Widget _buildNotFoundScaffold() => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: _accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  size: 36,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Photo not found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This photo may have been deleted.',
                style: TextStyle(fontSize: 13, color: _inkSubtle),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _goBack(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );

  // ── Main detail scaffold ──────────────────────────────────────────────────
}
