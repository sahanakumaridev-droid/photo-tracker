import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/network_quality.dart';
import '../../../core/storage/attempt_snapshot_store.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/storage/upload_queue.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/file_number.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/delivery_style.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/repository_providers.dart';
import 'location_picker_map.dart';

/// Attempt upload lifecycle: idle → uploading → processing → success | failed.
enum AttemptUploadState { idle, uploading, processing, success, failed }

/// Owns every field and piece of business logic for a new or resumed attempt.
/// Created once by ResumeAttemptScreen and injected into the composer
/// so the single-screen form observes one draft.
///
/// `BuildContext`/`WidgetRef` are never stored on the controller — methods
/// that need them (dialogs, provider reads) take them as parameters, passed
/// in by whichever screen is presenting at the time.
class AttemptDraftController extends ChangeNotifier {
  AttemptDraftController({this.initialProfileId, this.seedProfile}) {
    poorNetwork = NetworkQualityService.instance.isPoor;
    // F5: auto-save the draft whenever a text field changes. Also forces a
    // rebuild via notifyListeners so hub/checklist "done" captions and the
    // Complete Attempt button's enabled state stay live across every field
    // (the old single-screen form only needed this for File Number since
    // everything else was already visible in the same build; here Pay
    // Rate/Notes/Served To can be edited on a different screen than the
    // hub that displays their status, so all six controllers need it).
    noteController.addListener(_onFieldChanged);
    addressController.addListener(_onFieldChanged);
    payRateController.addListener(_onFieldChanged);
    servedToController.addListener(_onFieldChanged);
    relationToController.addListener(_onFieldChanged);
    fileNumberController.addListener(_onFieldChanged);
  }

  // ── Design tokens (shared by the dialogs/snackbars this controller shows) ──
  static const Color errorRed = Color(0xFFEF4444);
  static const Color successGreen = Color(0xFF10B981);

  // Radius used to surface "Nearby" profiles first in the profile picker,
  // and to find candidates for the post-upload "Duplicate Attempt?" offer.
  static const double kProfileProximityFt = 200;

  static const int kMaxAttemptsPerJob = 6;

  static const List<String> kServedToPresets = [
    'Same as profile',
    'John Doe',
    'Jane Doe',
  ];

  /// "Add to Existing Profile" — pre-selects that profile and locks
  /// profile/company fields so only attempt-specific data is editable. The
  /// Profile's stored location is never copied into the attempt; GPS is
  /// still captured fresh (see [fetchLocation]).
  final int? initialProfileId;

  /// Profile object from the screen that opened Add Attempt (create flow /
  /// map pin). Used when the list API omits file_number.
  final ProfileModel? seedProfile;

  /// True when opened via "Add to Existing Profile" (`?profileId=`).
  bool get isExistingProfileAttempt => initialProfileId != null;

  /// Set by [loadExistingAttempt] when this draft was loaded from a real,
  /// already-saved server Attempt (Attempts Dashboard → Resume). Seeds the
  /// `attemptId` loop variable in [upload] so newly added photos attach to
  /// the same Attempt row instead of creating a new one.
  int? existingAttemptId;

  /// Number of photos already uploaded to [existingAttemptId] on the server
  /// — display-only. An existing attempt's remote photos can't be loaded
  /// into [selectedImages] (that list is local-file-path only), so they're
  /// surfaced as a count (see `attempt_photos_screen.dart`), not thumbnails.
  int existingPhotoCount = 0;

  String? _localSnapshotId;

  /// Stable key for this draft's slot in [AttemptSnapshotStore]. Existing
  /// attempts key off their server id (so cached edits always land back on
  /// the right record); brand-new attempts get a lazily-generated id that
  /// persists for the life of this controller, so repeated Quick Saves of
  /// the same in-progress attempt update one slot instead of piling up.
  String get snapshotId => existingAttemptId != null
      ? 'existing_$existingAttemptId'
      : (_localSnapshotId ??= const Uuid().v4());

  bool _disposed = false;

  // ── Upload state ────────────────────────────────────────────────────────
  AttemptUploadState uploadState = AttemptUploadState.idle;
  int? lastUploadedPhotoId;
  int uploadedCount = 0;

  // ── State ───────────────────────────────────────────────────────────────
  // Multi-photo: each entry in selectedImages has a matching takenAts entry.
  final List<File> selectedImages = [];
  final List<String?> takenAts = [];
  ProfileModel? selectedProfile;

  /// Other profiles this attempt should be duplicated onto after upload.
  final Set<int> linkProfileIds = {};
  String companyId = kDefaultCompanyId;
  double? latitude;
  double? longitude;
  double? gpsAccuracy;
  bool isLoadingLocation = false;
  bool locationError = false;
  String? locationErrorMsg;
  bool isEditingAddress = false;
  String selectedCategory = kDefaultCategory;
  // F1: when the user chooses to append to an existing pin.
  int? locationGroupId;
  // Prevent the nearby-pin prompt from firing more than once per location.
  bool nearbyCheckDone = false;

  final noteController = TextEditingController();
  final addressController = TextEditingController();
  final payRateController = TextEditingController(); // F7
  final servedToController = TextEditingController();
  final relationToController = TextEditingController();
  final fileNumberController = TextEditingController();

  // Defaults to true; the user must explicitly flip it off. When false the
  // Served To / Relation To fields don't apply and are hidden.
  String attemptStatus = kDefaultAttemptStatus;
  bool get isSuccessfulAttempt => attemptStatus == kAttemptStatusSuccessful;

  // Names the user has typed via "New name" — remembered across uploads so
  // they show up as quick-select options next time, not just a one-off entry.
  List<String> customServedToNames = LocalStorage.getServedToCustomNames();

  String? deliveryStyle;
  final imagePicker = ImagePicker();

  /// When true, GPS/time come from a poor-network snapshot and must not be
  /// overwritten by a fresh fix when signal returns.
  bool locationFrozenFromCache = false;
  bool poorNetwork = false;
  bool _snapshotBusy = false;
  Timer? _snapshotTimer;
  StreamSubscription<bool>? _poorSub;
  /// Avoid re-prompting the same snapshot on every probe tick.
  String? _offeredSnapshotAt;

  /// Fired when poor network → good network transitions. The hub screen
  /// (always mounted, unlike pushed sub-screens) wires this to call
  /// [offerCachedAttemptReview] with its own context — the controller itself
  /// never stores a BuildContext.
  VoidCallback? onNetworkImproved;

  void _onFieldChanged() {
    notifyListeners();
    saveDraft();
  }

  /// Runs once, from the hub screen's initState post-frame callback —
  /// replicates the old `_UploadScreenV2State.initState` body exactly.
  Future<void> init(BuildContext context, WidgetRef ref) async {
    // Draft/snapshot restore runs first so dialogs never overlap the
    // nearby-pin prompt. Fresh GPS is skipped when the restore froze
    // location from cache.
    final restoredFrozen = await maybeRestoreSnapshotOrDraft(context, ref);
    if (_disposed) return;
    await maybeApplyInitialProfile(ref);
    if (_disposed) return;
    if (!restoredFrozen) {
      unawaited(fetchLocation(context, ref));
    }
    startPoorNetworkMonitoring();
  }

  @override
  void dispose() {
    _disposed = true;
    _snapshotTimer?.cancel();
    _poorSub?.cancel();
    noteController.dispose();
    addressController.dispose();
    payRateController.dispose();
    servedToController.dispose();
    relationToController.dispose();
    fileNumberController.dispose();
    super.dispose();
  }

  void startPoorNetworkMonitoring() {
    _poorSub?.cancel();
    _poorSub = NetworkQualityService.instance.onPoorChanged.listen((poor) {
      if (_disposed) return;
      final wasPoor = poorNetwork;
      poorNetwork = poor;
      notifyListeners();
      if (poor) {
        // High latency / offline: freeze the location+time from *now*
        // (while service is bad) and continually snapshot form inputs so
        // reconnect never substitutes a later GPS fix.
        unawaited(_beginPoorNetworkCaching());
      } else {
        _snapshotTimer?.cancel();
        _snapshotTimer = null;
        // Signal improved — offer the frozen snapshot for review/save.
        if (wasPoor) onNetworkImproved?.call();
      }
    });
    if (poorNetwork) {
      unawaited(_beginPoorNetworkCaching());
    }
  }

  /// Freeze current/last-known geotag, stamp missing photo times, start the
  /// 10s continual snapshot loop, and write an immediate snapshot.
  Future<void> _beginPoorNetworkCaching() async {
    if (_disposed) return;
    await _freezeLocationForPoorNetwork();
    if (_disposed) return;
    _ensureSnapshotTimer();
    await writeAttemptSnapshot(source: 'poor_network_auto');
  }

  /// Lock lat/lng (+ any unset photo capture times) to whatever we know
  /// while signal is bad — last-known GPS if the form has no fix yet.
  Future<void> _freezeLocationForPoorNetwork() async {
    if (locationFrozenFromCache) {
      _stampMissingTakenAts();
      return;
    }
    if (latitude == null || longitude == null) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && !_disposed) {
          latitude = last.latitude;
          longitude = last.longitude;
          gpsAccuracy = last.accuracy;
        }
      } catch (_) {}
    }
    if (_disposed) return;
    _stampMissingTakenAts();
    if (latitude != null && longitude != null) {
      locationFrozenFromCache = true;
      notifyListeners();
    }
  }

  void _stampMissingTakenAts() {
    for (var i = 0; i < takenAts.length; i++) {
      takenAts[i] ??= DateTime.now().toUtc().toIso8601String();
    }
  }

  void _ensureSnapshotTimer() {
    if (_snapshotTimer != null) return;
    _snapshotTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!poorNetwork || _disposed) return;
      unawaited(writeAttemptSnapshot(source: 'poor_network_auto'));
    });
  }

  Map<String, dynamic> attemptPayload({required String source}) => {
        'note': noteController.text,
        'address': addressController.text,
        'category': selectedCategory,
        'payRate': payRateController.text,
        'servedTo': servedToController.text,
        'relationTo': relationToController.text,
        'fileNumber': fileNumberController.text,
        'attemptStatus': attemptStatus,
        'successful': isSuccessfulAttempt,
        'completionType': deliveryStyle,
        'company': companyId,
        'profileId': selectedProfile?.id,
        'profileName': selectedProfile?.name,
        'takenAts': List<String?>.from(takenAts),
        'latitude': latitude,
        'longitude': longitude,
        'gpsAccuracy': gpsAccuracy,
        'locationGroupId': locationGroupId,
        'source': source,
        'existingAttemptId': existingAttemptId,
      };

  bool get canQuickSave =>
      selectedProfile != null &&
      latitude != null &&
      longitude != null &&
      uploadState == AttemptUploadState.idle;

  /// True once this attempt has a photo either newly added this session or
  /// already sitting on the server from before (see [loadExistingAttempt] /
  /// [existingPhotoCount]) — resuming an attempt that already has a photo
  /// must not re-demand a brand-new one just to finish editing other fields.
  bool get hasPhoto => selectedImages.isNotEmpty || existingPhotoCount > 0;

  bool get canUpload =>
      hasPhoto &&
      selectedProfile != null &&
      latitude != null &&
      uploadState == AttemptUploadState.idle;

  /// Returns a hint about what's still needed before Complete Attempt is
  /// enabled.
  String missingFieldsHint() {
    final missing = <String>[];
    if (!hasPhoto) missing.add('photo');
    if (selectedProfile == null) missing.add('profile');
    if (latitude == null && !isLoadingLocation) missing.add('location');
    if (isLoadingLocation) return 'Waiting for GPS…';
    if (missing.isEmpty) return '';
    return 'Still needed: ${missing.join(', ')}';
  }

  /// Continual / manual snapshot. Freezes the location+timestamps currently
  /// on the form (or last-known GPS if still null and not already frozen).
  /// Subsequent snapshots while frozen update form inputs/photos only —
  /// lat/lng and already-stamped [takenAts] stay as cached.
  Future<void> writeAttemptSnapshot({required String source}) async {
    if (_snapshotBusy) return;
    if (selectedProfile == null && selectedImages.isEmpty) return;

    // Prefer last-known GPS only when we still have no coords and nothing
    // is locked yet. Never replace a frozen geotag.
    if (!locationFrozenFromCache &&
        (latitude == null || longitude == null)) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && !_disposed) {
          latitude = last.latitude;
          longitude = last.longitude;
          gpsAccuracy = last.accuracy;
          notifyListeners();
        }
      } catch (_) {}
    }
    if (latitude == null || longitude == null) return;

    // Stamp missing capture times once; never regenerate existing ones.
    _stampMissingTakenAts();

    _snapshotBusy = true;
    try {
      await AttemptSnapshotStore.save(
        id: snapshotId,
        payload: attemptPayload(source: source),
        photoFiles: List<File>.from(selectedImages),
      );
      // Quick Save and poor-network autosave both lock GPS/time so reconnect
      // cannot substitute the user's later location.
      if (!_disposed &&
          (source == 'quick_save' || source == 'poor_network_auto')) {
        locationFrozenFromCache = true;
        notifyListeners();
      }
    } finally {
      _snapshotBusy = false;
    }
  }

  /// Returns true when the attempt was actually cached, so callers can pop
  /// back to the previous screen only on a real save (not on a validation
  /// failure like "select a profile first").
  Future<bool> quickSaveAttempt(BuildContext context) async {
    if (!canQuickSave) {
      showSnack(
        context,
        selectedProfile == null
            ? 'Select a profile before quick save'
            : 'Waiting for location…',
        isError: true,
      );
      return false;
    }
    HapticFeedback.mediumImpact();
    await writeAttemptSnapshot(source: 'quick_save');
    if (_disposed) return false;
    locationFrozenFromCache = true;
    notifyListeners();
    if (context.mounted) {
      showSnack(
        context,
        'Attempt cached with this location & time. '
        'When signal improves, review and upload — GPS will not be refreshed.',
      );
    }
    return true;
  }

  /// Falls back to the plain pin-draft check. Cached photo/GPS snapshots
  /// (Quick Save / Save & Exit / poor-network auto-save) are no longer
  /// auto-offered here on blank-new-attempt open — with multiple snapshots
  /// now cacheable at once (see [AttemptSnapshotStore]), the Attempts
  /// Dashboard's "Quick Saved" list is the explicit, unambiguous place to
  /// resume one instead of guessing which single snapshot to pop up.
  /// Returns true when location was restored from a frozen snapshot.
  Future<bool> maybeRestoreSnapshotOrDraft(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await maybeRestoreDraft(context, ref);
    return locationFrozenFromCache;
  }

  Future<void> offerCachedAttemptReview(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (_disposed || uploadState != AttemptUploadState.idle) return;
    final snapshot = await AttemptSnapshotStore.read(snapshotId);
    if (_disposed || snapshot == null) return;
    final at = snapshot['snapshotAt'] as String?;
    if (at != null && at == _offeredSnapshotAt) return;
    if (!context.mounted) return;

    final profileName = snapshot['profileName'] as String?;
    final address = (snapshot['address'] as String?)?.trim();
    final lat = snapshot['latitude'];
    final lng = snapshot['longitude'];
    final photoCount = (snapshot['photoPaths'] as List?)?.length ?? 0;

    final lines = <String>[
      if (profileName != null && profileName.isNotEmpty)
        'Profile: $profileName',
      if (address != null && address.isNotEmpty) 'Location: $address',
      if (lat != null && lng != null)
        'Cached GPS: '
            '${(lat as num).toStringAsFixed(5)}, '
            '${(lng as num).toStringAsFixed(5)}',
      if (photoCount > 0)
        '$photoCount photo${photoCount == 1 ? '' : 's'} cached',
      if (at != null) 'Snapshot: $at',
    ];

    final review = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Network improved'),
        content: Text(
          'Your latest cached attempt is ready to review and save.\n\n'
          '${lines.isEmpty ? '' : '${lines.join('\n')}\n\n'}'
          'Upload will use the cached location and capture time from when '
          'signal was bad — not your current GPS or clock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Review & Save'),
          ),
        ],
      ),
    );
    if (_disposed) return;
    // Remember we already offered this snapshot either way, so probe ticks
    // don't re-spam the dialog. "Later" still leaves the draft frozen and
    // visible under Drafts on the Attempts dashboard.
    _offeredSnapshotAt = at;
    if (review == true) {
      await applyAttemptMap(snapshot, freezeLocation: true, ref: ref);
      if (context.mounted) {
        showSnack(
          context,
          'Cached location locked — review fields, then upload.',
        );
      }
    } else if (!_disposed) {
      // Keep freeze even if they dismiss — reconnect must not refresh GPS.
      locationFrozenFromCache = true;
      notifyListeners();
    }
  }

  /// Loads a locally-cached snapshot (Attempts Dashboard → "Quick Saved" →
  /// tap a card) into this draft. Adopts the snapshot's own id as this
  /// controller's [snapshotId] — for an existing-attempt snapshot that's
  /// already true via [existingAttemptId]; for a brand-new-attempt snapshot
  /// this makes further edits/Quick Saves overwrite the same cached slot
  /// instead of forking a duplicate.
  Future<void> resumeFromLocalSnapshot(
    Map<String, dynamic> snapshot, {
    required WidgetRef ref,
  }) async {
    existingAttemptId = snapshot['existingAttemptId'] as int?;
    if (existingAttemptId == null) {
      _localSnapshotId = snapshot['snapshotId'] as String?;
    }
    await applyAttemptMap(snapshot, freezeLocation: true, ref: ref);
  }

  Future<void> applyAttemptMap(
    Map<String, dynamic> draft, {
    required bool freezeLocation,
    required WidgetRef ref,
  }) async {
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
        ? rawTakenAts.map((e) => e as String?).toList()
        : List<String?>.filled(restoredImages.length, null);

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
      } catch (_) {}
    }

    if (_disposed) return;
    locationFrozenFromCache = freezeLocation;
    noteController.text = (draft['note'] ?? '') as String;
    addressController.text = (draft['address'] ?? '') as String;
    payRateController.text = (draft['payRate'] ?? '') as String;
    servedToController.text = (draft['servedTo'] ?? '') as String;
    relationToController.text = (draft['relationTo'] ?? '') as String;
    fileNumberController.text = (draft['fileNumber'] ?? '') as String;
    attemptStatus = attemptStatusFromLegacy(
      attemptStatus: draft['attemptStatus'] as String?,
      successful: draft['successful'] as bool?,
    );
    final savedStyle = draft['completionType'] as String?;
    deliveryStyle = kDeliveryStyles.contains(savedStyle) ? savedStyle : null;
    selectedCategory = (draft['category'] ?? kDefaultCategory) as String;
    final savedCompany = draft['company'] as String?;
    companyId = companyById(savedCompany)?.id ?? kDefaultCompanyId;
    if (!companyOrDefault(companyId).allowsPriority(selectedCategory)) {
      selectedCategory = defaultPriorityForCompany(companyId);
    }
    selectedImages
      ..clear()
      ..addAll(restoredImages);
    takenAts
      ..clear()
      ..addAll(restoredTakenAts);
    while (takenAts.length < selectedImages.length) {
      takenAts.add(null);
    }
    latitude = (draft['latitude'] as num?)?.toDouble();
    longitude = (draft['longitude'] as num?)?.toDouble();
    gpsAccuracy = (draft['gpsAccuracy'] as num?)?.toDouble();
    locationGroupId = draft['locationGroupId'] as int?;
    if (restoredProfile != null) {
      selectedProfile = restoredProfile;
      companyId = companyOrDefault(restoredProfile.company).id;
      if (!companyOrDefault(companyId).allowsPriority(selectedCategory)) {
        selectedCategory = defaultPriorityForCompany(companyId);
      }
    }
    notifyListeners();
  }

  /// Loads a real, already-saved server [Attempt] into the draft for
  /// editing — used by the Attempts Dashboard's Resume button (a genuine
  /// existing record, not a local draft/snapshot). Builds the same
  /// camelCase map [applyAttemptMap] already expects and reuses it as-is, so
  /// every scalar field restores through the exact same path local-draft
  /// resume already uses. `company` is left unset — `applyAttemptMap`
  /// resolves it from the matched [ProfileModel] once `profileId` restores
  /// it — and `gpsAccuracy` is left absent so GPS re-captures fresh (see
  /// [fetchLocation]).
  Future<void> loadExistingAttempt(
    Attempt attempt, {
    required WidgetRef ref,
  }) async {
    // Set before populating fields (not after) so the saveDraft/
    // writeAttemptSnapshot guards above are already active for the
    // population itself, not just for edits made afterward.
    existingAttemptId = attempt.id;
    existingPhotoCount = attempt.photos.length;
    // Also clear anything already sitting in this attempt's own snapshot
    // slot — it may hold a stale local snapshot from before this reload;
    // either way it must not surface as a stale "Quick Saved" card once
    // fresh server data has just been loaded on top of it.
    await LocalStorage.clearPinDraft();
    await AttemptSnapshotStore.clear(snapshotId);
    final map = <String, dynamic>{
      'note': attempt.note,
      'address': attempt.address,
      'payRate': attempt.payRate?.toString(),
      'servedTo': attempt.servedTo,
      'relationTo': attempt.relationTo,
      'fileNumber': attempt.fileNumber,
      'attemptStatus': attempt.attemptStatus,
      'completionType': attempt.completionType,
      'category': attempt.category,
      'profileId': attempt.profileId,
      'latitude': attempt.latitude,
      'longitude': attempt.longitude,
    };
    await applyAttemptMap(map, freezeLocation: false, ref: ref);
    if (_disposed) return;
    notifyListeners();
  }

  // ── F5: Draft auto-save & recovery ────────────────────────────────────────
  // The local pin-draft/snapshot slot exists to recover unsaved work that has
  // no server record yet. An attempt loaded via [loadExistingAttempt] already
  // has a server id ([existingAttemptId]) — letting its field population (or
  // further edits) write into that same shared slot would later surface a
  // stale "Resume Draft?" prompt when the user starts an unrelated new
  // attempt, offering to resume data that actually belongs to a different,
  // already-existing attempt. So both auto-save paths are no-ops while
  // editing a known existing attempt.
  void saveDraft() {
    if (existingAttemptId != null) return;
    if (selectedImages.isEmpty && selectedProfile == null) return;
    LocalStorage.savePinDraft(jsonEncode({
      ...attemptPayload(source: 'draft'),
      'photoPaths': selectedImages.map((f) => f.path).toList(),
    }));
    // While signal is poor, keep the durable frozen snapshot fresh too.
    if (poorNetwork) {
      unawaited(writeAttemptSnapshot(source: 'poor_network_auto'));
    }
  }

  Future<void> maybeRestoreDraft(BuildContext context, WidgetRef ref) async {
    final raw = LocalStorage.getPinDraft();
    if (raw == null || _disposed || !context.mounted) return;
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
    if (_disposed) return;
    await applyAttemptMap(draft, freezeLocation: false, ref: ref);
  }

  /// Locks the given profile for an "Add to Existing Profile" attempt.
  /// Always wins over a resumed draft's profile so the user cannot
  /// accidentally attach the attempt to a different profile.
  Future<void> maybeApplyInitialProfile(WidgetRef ref) async {
    final id = initialProfileId;
    if (id == null) return;
    ProfileModel? found =
        seedProfile != null && seedProfile!.id == id ? seedProfile : null;
    try {
      final profiles = await ref.read(profilesProvider.future);
      if (_disposed) return;
      for (final p in profiles) {
        if (p.id != id) continue;
        final seedFn = (found?.fileNumber ?? '').trim();
        final listFn = (p.fileNumber ?? '').trim();
        found = listFn.isNotEmpty
            ? p
            : (seedFn.isNotEmpty ? p.copyWith(fileNumber: seedFn) : p);
        break;
      }
    } catch (_) {/* keep seed */}
    if (_disposed || found == null) return;
    final localFn = LocalStorage.fileNumberForProfile(found.id);
    if ((found.fileNumber ?? '').trim().isEmpty &&
        localFn != null &&
        localFn.trim().isNotEmpty) {
      found = found.copyWith(fileNumber: localFn.trim());
    }
    selectedProfile = found;
    companyId = companyOrDefault(found.company).id;
    if (companyOrDefault(companyId).allowsPriority(found.serviceType)) {
      selectedCategory = found.serviceType;
    } else {
      selectedCategory = defaultPriorityForCompany(companyId);
    }
    notifyListeners();
    saveDraft();
    unawaited(_prefillLockedProfile(found, ref));
  }

  void _prefillProfileStandingFields(ProfileModel p, {bool force = false}) {
    final company = companyOrDefault(p.company);
    if (force ||
        !company.allowsPriority(selectedCategory)) {
      if (company.allowsPriority(p.serviceType)) {
        selectedCategory = p.serviceType;
      } else {
        selectedCategory = defaultPriorityForCompany(p.company);
      }
    }
    final style = (p.deliveryStyle ?? '').trim();
    if (style.isNotEmpty && kDeliveryStyles.contains(style)) {
      if (force || deliveryStyle == null) deliveryStyle = style;
    }
    if (p.payRate != null &&
        (force || payRateController.text.trim().isEmpty)) {
      payRateController.text = '${p.payRate}';
    }
    final standingFn = (p.fileNumber ?? '').trim();
    if (standingFn.isNotEmpty &&
        (force || fileNumberController.text.trim().isEmpty)) {
      fileNumberController.text = standingFn;
    }
    if (addressController.text.trim().isEmpty) {
      final parts = [
        p.address,
        p.city,
        p.state,
        p.postalCode,
      ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
      if (parts.isNotEmpty) addressController.text = parts.join(', ');
    }
  }

  /// Records GPS at the moment a photo is captured so the attempt tag
  /// matches the shutter, not a later form-open location.
  Future<void> _stampGeotagAtCapture() async {
    if (locationFrozenFromCache && latitude != null) return;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await LocationService.getCurrentLocation();
      if (pos == null || _disposed) return;
      latitude = pos.latitude;
      longitude = pos.longitude;
      gpsAccuracy = pos.accuracy;
      locationError = false;
      locationErrorMsg = null;
      notifyListeners();
      saveDraft();
      final address = await LocationService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (!_disposed &&
          address != null &&
          address.isNotEmpty &&
          addressController.text.trim().isEmpty) {
        addressController.text = address;
      }
    } catch (_) {}
  }

  // ── Location ────────────────────────────────────────────────────────────
  Future<void> fetchLocation(BuildContext context, WidgetRef ref) async {
    // Cached attempts must keep the frozen geotag from when signal was bad.
    if (locationFrozenFromCache) {
      isLoadingLocation = false;
      locationError = false;
      notifyListeners();
      return;
    }
    isLoadingLocation = true;
    locationError = false;
    locationErrorMsg = null;
    addressController.clear();
    notifyListeners();
    try {
      // 1. Check permission
      final granted = await LocationService.requestLocationPermission();
      if (_disposed) return;
      if (!granted) {
        locationError = true;
        locationErrorMsg =
            'Location permission denied. Please enable it in Settings.';
        notifyListeners();
        return;
      }

      // 2. Check service enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (_disposed) return;
      if (!serviceEnabled) {
        locationError = true;
        locationErrorMsg =
            'Location services are off. Please enable GPS in Settings.';
        notifyListeners();
        return;
      }

      // 3. Fast first paint — use last-known position
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && !_disposed) {
          latitude = last.latitude;
          longitude = last.longitude;
          gpsAccuracy = last.accuracy;
          notifyListeners();
        }
      } catch (_) {}

      // 4. Fetch fresh high-accuracy fix (with retry in LocationService)
      final freshPos = await LocationService.getCurrentLocation();
      if (_disposed) return;
      if (freshPos == null) {
        locationError = latitude == null;
        locationErrorMsg = latitude == null
            ? 'Could not get your location. Tap Refresh to try again.'
            : null;
        notifyListeners();
        return;
      }

      latitude = freshPos.latitude;
      longitude = freshPos.longitude;
      gpsAccuracy = freshPos.accuracy;
      locationError = false;
      locationErrorMsg = null;
      nearbyCheckDone = false; // fresh location — re-arm the check
      notifyListeners();
      // F5: persist the location into the draft right away.
      saveDraft();
      // F1: proactively check for nearby pins as soon as GPS is ready, so
      // the user is prompted before filling out the form.
      unawaited(checkNearbyAndMaybeReuse(context, ref));

      // Reverse geocode for address (ZIP is inline in the address string)
      final address = await LocationService.reverseGeocode(
        freshPos.latitude,
        freshPos.longitude,
      );
      if (!_disposed && address != null && address.isNotEmpty) {
        addressController.text = address;
      }
    } catch (e) {
      debugPrint('[Upload] location error: $e');
      if (!_disposed) {
        locationError = latitude == null;
        locationErrorMsg = latitude == null
            ? 'Location unavailable. Tap Refresh to try again.'
            : null;
        notifyListeners();
      }
    } finally {
      if (!_disposed) {
        isLoadingLocation = false;
        notifyListeners();
      }
    }
  }

  /// Applies the result of the full-screen map picker (pushed by the Location
  /// screen itself — see `attempt_location_screen.dart`) back onto the draft.
  Future<void> applyPickedLocation(
    PickedLocation picked,
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (locationFrozenFromCache) {
      if (context.mounted) {
        showSnack(
          context,
          'Location is locked from cache. Unlock from the banner to change it.',
          isError: true,
        );
      }
      return;
    }
    latitude = picked.latLng.latitude;
    longitude = picked.latLng.longitude;
    locationError = false;
    nearbyCheckDone = false; // new location — re-arm the nearby check
    notifyListeners();
    // F5: persist the picked location into the draft right away.
    saveDraft();
    // F1: re-run proactive nearby check for the newly picked location.
    unawaited(checkNearbyAndMaybeReuse(context, ref));

    // Prefer the address the picker already resolved (matches the pin
    // exactly); only reverse-geocode as a fallback if it didn't have one.
    if (picked.address != null && picked.address!.isNotEmpty) {
      addressController.text = picked.address!;
      isLoadingLocation = false;
      notifyListeners();
      return;
    }
    isLoadingLocation = true;
    notifyListeners();
    try {
      final address = await LocationService.reverseGeocode(
        picked.latLng.latitude,
        picked.latLng.longitude,
      );
      if (!_disposed && address != null && address.isNotEmpty) {
        addressController.text = address;
      }
    } catch (e) {
      debugPrint('[MapPicker] reverse geocode error: $e');
    } finally {
      if (!_disposed) {
        isLoadingLocation = false;
        notifyListeners();
      }
    }
  }

  // ── Camera / Gallery ────────────────────────────────────────────────────
  Future<void> pickImage(BuildContext context, ImageSource source) async {
    HapticFeedback.lightImpact();
    if (source == ImageSource.camera) {
      await pickFromCamera(context);
    } else {
      await pickFromGallery(context);
    }
  }

  Future<void> pickFromCamera(BuildContext context) async {
    // Check camera permission explicitly on both iOS and Android
    final status = await Permission.camera.status;

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        showSnack(
          context,
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
        if (context.mounted) {
          showSnack(
            context,
            'Camera permission is required to take photos.',
            isError: true,
            settingsAction: result.isPermanentlyDenied,
          );
        }
        return;
      }
    }

    await openPicker(context, ImageSource.camera);
  }

  Future<void> pickFromGallery(BuildContext context) async {
    // On iOS 14+, image_picker uses PHPickerViewController which does NOT
    // require full photo library permission — it works with limited access
    // too. We must treat isLimited as granted, otherwise the gallery never
    // opens even when the user tapped "Select Photos" in the system dialog.
    final status = await Permission.photos.status;

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        showSnack(
          context,
          'Photo library access blocked. Enable it in Settings.',
          isError: true,
          settingsAction: true,
        );
      }
      return;
    }

    // isGranted OR isLimited (iOS 14 "Select Photos") → proceed directly
    if (status.isGranted || status.isLimited) {
      await openPicker(context, ImageSource.gallery);
      return;
    }

    // isDenied / isRestricted / notDetermined → request
    final result = await Permission.photos.request();

    // isLimited counts as success — user picked specific photos
    if (result.isGranted || result.isLimited) {
      await openPicker(context, ImageSource.gallery);
    } else {
      if (context.mounted) {
        showSnack(
          context,
          'Photo library permission is required to pick photos.',
          isError: true,
          settingsAction: result.isPermanentlyDenied,
        );
      }
    }
  }

  Future<void> openPicker(BuildContext context, ImageSource source) async {
    try {
      // Gallery: allow picking multiple images at once.
      if (source == ImageSource.gallery) {
        // Pick at full resolution so EXIF (capture date) survives; the
        // watermark step downscales the image for upload.
        final picked = await imagePicker.pickMultiImage();
        if (picked.isEmpty || _disposed) return;
        HapticFeedback.mediumImpact();
        final provisional = DateTime.now().toUtc().toIso8601String();
        for (final x in picked) {
          selectedImages.add(File(x.path));
          takenAts.add(provisional);
        }
        notifyListeners();
        // Refine each timestamp from EXIF in the background.
        for (var i = selectedImages.length - picked.length;
            i < selectedImages.length;
            i++) {
          final captured = await readCaptureTimeIso(selectedImages[i]);
          if (_disposed) return;
          takenAts[i] = captured;
          notifyListeners();
        }
        saveDraft();
        unawaited(_stampGeotagAtCapture());
        return;
      }

      // Camera: single shot. Full resolution so EXIF survives.
      final picked = await imagePicker.pickImage(source: source);
      if (picked != null && !_disposed) {
        HapticFeedback.mediumImpact();
        final provisional = DateTime.now().toUtc().toIso8601String();
        selectedImages.add(File(picked.path));
        takenAts.add(provisional);
        notifyListeners();
        final captured = await readCaptureTimeIso(File(picked.path));
        if (!_disposed) {
          takenAts[takenAts.length - 1] = captured;
          notifyListeners();
        }
        saveDraft();
        unawaited(_stampGeotagAtCapture());
      }
    } on PlatformException catch (e) {
      debugPrint('[Picker] PlatformException: ${e.code} – ${e.message}');
      final isPermissionError = e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied' ||
          e.code == 'PHPickerViewController/permission_denied';
      if (context.mounted) {
        showSnack(
          context,
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
      if (context.mounted) {
        showSnack(
          context,
          'Could not open '
          '${source == ImageSource.camera ? "camera" : "gallery"}',
          isError: true,
        );
      }
    }
  }

  void removeImage(int index) {
    selectedImages.removeAt(index);
    if (index < takenAts.length) {
      takenAts.removeAt(index);
    }
    notifyListeners();
    saveDraft();
  }

  void showSnack(
    BuildContext context,
    String msg, {
    bool isError = false,
    bool settingsAction = false,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
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
        backgroundColor: isError ? errorRed : successGreen,
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

  // ── Field setters (plain data callbacks from screen-owned UI) ──────────────
  void setCompany(String id) {
    companyId = id;
    // Drop a selected profile that belongs to another company.
    if (selectedProfile != null &&
        companyOrDefault(selectedProfile!.company).id != id) {
      selectedProfile = null;
    }
    if (!companyOrDefault(id).allowsPriority(selectedCategory)) {
      selectedCategory = defaultPriorityForCompany(id);
    }
    notifyListeners();
    saveDraft();
  }

  void setSelectedProfile(ProfileModel p, {WidgetRef? ref}) {
    selectedProfile = p;
    linkProfileIds.clear();
    companyId = companyOrDefault(p.company).id;
    if (!companyOrDefault(companyId).allowsPriority(selectedCategory)) {
      selectedCategory = defaultPriorityForCompany(companyId);
    }
    notifyListeners();
    saveDraft();
    // Prefill from this profile's most recent attempt (delivery style / pay
    // rate tend to repeat per-profile) — only for a brand-new attempt with
    // nothing typed yet; never clobber a real resumed record or edits the
    // user already made.
    if (ref != null && existingAttemptId == null) {
      unawaited(_prefillLockedProfile(p, ref));
    }
  }

  /// Latest attempt first (file #, pay, delivery, served to), then standing
  /// profile fields fill whatever is still empty — never clobber typed values.
  Future<void> _prefillLockedProfile(ProfileModel p, WidgetRef ref) async {
    await _prefillFromLatestAttempt(p.id, ref);
    if (_disposed || selectedProfile?.id != p.id) return;
    _prefillProfileStandingFields(p, force: isExistingProfileAttempt);
    notifyListeners();
    saveDraft();
  }

  Future<void> _prefillFromLatestAttempt(int profileId, WidgetRef ref) async {
    try {
      final attempts = await ref.read(profileAttemptsProvider(profileId).future);
      if (_disposed || selectedProfile?.id != profileId) return;
      var changed = false;
      if (fileNumberController.text.trim().isEmpty) {
        final fromProfile = _fileNumberFromAttempts(attempts) ??
            _fileNumberFromPhotos(profileId, ref);
        if (fromProfile != null) {
          fileNumberController.text = fromProfile;
          changed = true;
        }
      }
      if (attempts.isEmpty) {
        if (changed) {
          notifyListeners();
          saveDraft();
        }
        return;
      }
      final latest = attempts.first;
      if (!isExistingProfileAttempt &&
          payRateController.text.trim().isEmpty &&
          latest.payRate != null) {
        payRateController.text = latest.payRate.toString();
        changed = true;
      }
      if (servedToController.text.trim().isEmpty &&
          (latest.servedTo ?? '').trim().isNotEmpty) {
        servedToController.text = latest.servedTo!.trim();
        changed = true;
      }
      if (relationToController.text.trim().isEmpty &&
          (latest.relationTo ?? '').trim().isNotEmpty) {
        relationToController.text = latest.relationTo!.trim();
        changed = true;
      }
      if (changed) {
        notifyListeners();
        saveDraft();
      }
    } catch (_) {
      // Best-effort convenience — silently skip on failure.
    }
  }

  String? _fileNumberFromAttempts(List<Attempt> attempts) {
    for (final a in attempts) {
      final fn = (a.fileNumber ?? '').trim();
      if (fn.isNotEmpty) return fn;
      for (final p in a.photos) {
        final pfn = (p.fileNumber ?? '').trim();
        if (pfn.isNotEmpty) return pfn;
      }
    }
    return null;
  }

  String? _fileNumberFromPhotos(int profileId, WidgetRef ref) {
    final photos = ref.read(photosProvider).valueOrNull;
    if (photos == null) return null;
    for (final p in photos) {
      if (p.profileId != profileId) continue;
      final fn = (p.fileNumber ?? '').trim();
      if (fn.isNotEmpty) return fn;
    }
    return null;
  }

  void setSelectedCategory(String value) {
    if (isExistingProfileAttempt) return;
    selectedCategory = value;
    notifyListeners();
    saveDraft();
  }

  void setDeliveryStyle(String? value) {
    if (selectedProfile != null) return;
    deliveryStyle = value;
    notifyListeners();
    saveDraft();
  }

  void setAttemptStatus(String value) {
    attemptStatus = value;
    notifyListeners();
    saveDraft();
  }

  void setServedTo(String value) {
    // Assigning .text below notifies noteController-style listeners
    // (_onFieldChanged), which already calls notifyListeners()+saveDraft().
    servedToController.text = value;
    if (value == 'Same as profile') relationToController.clear();
  }

  Future<void> addCustomServedToName(String name) async {
    await LocalStorage.addServedToCustomName(name);
    customServedToNames = LocalStorage.getServedToCustomNames();
    notifyListeners();
  }

  void toggleEditingAddress() {
    isEditingAddress = !isEditingAddress;
    notifyListeners();
  }

  /// Unlocks a cached/frozen location so a fresh GPS fix can be taken.
  void unlockLocationFromCache() {
    locationFrozenFromCache = false;
    notifyListeners();
  }

  // Profile IDs with a photo within kProfileProximityFt of the current
  // upload location — surfaced first in the picker so the right profile is
  // easy to find without scrolling/searching a long roster.
  Set<int> nearbyProfileIds(WidgetRef ref) {
    if (latitude == null || longitude == null) return {};
    final photos = ref.read(photosProvider).valueOrNull ?? const [];
    final ids = <int>{};
    for (final p in photos) {
      if (p.profileId == null) continue;
      final km = LocationService.calculateDistance(
          latitude!, longitude!, p.latitude, p.longitude);
      if (km * 3280.84 <= kProfileProximityFt) ids.add(p.profileId!);
    }
    return ids;
  }

  // ── Upload ──────────────────────────────────────────────────────────────
  Future<void> upload(BuildContext context, WidgetRef ref) async {
    // Guard: prevent duplicate submissions
    if (uploadState == AttemptUploadState.uploading ||
        uploadState == AttemptUploadState.processing) {
      return;
    }

    if (selectedImages.isEmpty) {
      showSnack(context, 'Please select at least one photo', isError: true);
      return;
    }
    if (selectedProfile == null) {
      showSnack(context, 'Please select a profile', isError: true);
      return;
    }
    if (latitude == null || longitude == null) {
      showSnack(context, 'Location required. Tap Refresh to retry.',
          isError: true);
      return;
    }
    if (!await confirmAttemptNearProfile(context)) return;

    final servedToValue = servedToController.text.trim();
    if (isSuccessfulAttempt &&
        servedToValue.isNotEmpty &&
        servedToValue != 'Same as profile' &&
        relationToController.text.trim().isEmpty) {
      showSnack(context, 'Please enter a relation for the person served',
          isError: true);
      return;
    }

    if (locationGroupId == null && !nearbyCheckDone) {
      await checkNearbyAndMaybeReuse(context, ref);
      if (_disposed) return;
    }

    HapticFeedback.mediumImpact();
    uploadState = AttemptUploadState.uploading;
    uploadedCount = 0;
    notifyListeners();

    final payRate = int.tryParse(payRateController.text.trim());
    final address = addressController.text.trim().isEmpty
        ? null
        : addressController.text.trim();
    final note = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();
    // Served To / Relation To only apply to successful attempts.
    final servedTo = (isSuccessfulAttempt && servedToValue.isNotEmpty)
        ? servedToValue
        : null;
    final relationTo = (isSuccessfulAttempt &&
            relationToController.text.trim().isNotEmpty)
        ? relationToController.text.trim()
        : null;
    final fromProfile = inheritedFileNumber(
      profileFileNumber: (selectedProfile?.fileNumber ?? '').trim().isNotEmpty
          ? selectedProfile!.fileNumber
          : (selectedProfile != null
              ? LocalStorage.fileNumberForProfile(selectedProfile!.id)
              : null),
      attemptFileNumber: fileNumberController.text,
    );
    final fileNumber = fromProfile.isNotEmpty ? fromProfile : kFileNumberNA;
    final profileStyle = (selectedProfile?.deliveryStyle ?? '').trim();
    final completionType = kDeliveryStyles.contains(profileStyle)
        ? profileStyle
        : null;

    // The watermark caption is now drawn as a live display overlay
    // (WatermarkCaption) in the feed + detail screens — from each photo's
    // metadata — and re-baked into the file only at export time. So the
    // ORIGINAL photo is uploaded/queued here; baking on upload would
    // double-stamp beneath the overlay. (Queue/geotag handling below unchanged.)
    final watermarked = List<File>.from(selectedImages);

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
        profileId: selectedProfile!.id,
        latitude: latitude!,
        longitude: longitude!,
        takenAt: takenAts[i] ?? DateTime.now().toUtc().toIso8601String(),
        address: address,
        note: note,
        category: selectedCategory,
        completionType: completionType,
        servedTo: servedTo,
        relationTo: relationTo,
        fileNumber: fileNumber,
        successful: isSuccessfulAttempt,
        attemptStatus: attemptStatus,
        payRate: payRate,
        locationGroupId: locationGroupId,
        profileName: selectedProfile!.name,
      );
      queueIds.add(q.id);
    }

    try {
      int? lastId;
      // Group the whole batch under one master pin. If we're adding to an
      // existing pin, [locationGroupId] is already set; otherwise the FIRST
      // uploaded photo becomes the group anchor and every following photo
      // attaches to it — so N photos make ONE profile/pin with N previews,
      // not N separate profiles.
      int? groupId = locationGroupId;
      // Seeded from an existing server Attempt (Resume flow) so newly added
      // photos attach to that same row instead of creating a new one.
      int? attemptId = existingAttemptId;
      for (var i = 0; i < watermarked.length; i++) {
        final uploaded = await ref.read(uploadPhotoProvider({
          'filePath': watermarked[i].path,
          'profileId': selectedProfile!.id,
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'servedTo': servedTo,
          'relationTo': relationTo,
          'fileNumber': fileNumber,
          'successful': isSuccessfulAttempt,
          'attemptStatus': attemptStatus,
          'attemptId': attemptId,
          'completionType': completionType,
          'note': note,
          'category': selectedCategory,
          'payRate': payRate,
          'takenAt': takenAts[i],
          'locationGroupId': groupId,
        }).future);
        // Sent — drop it from the queue so the drainer can't re-send it.
        await UploadQueueService.instance.remove(queueIds[i]);
        lastId = uploaded.id;
        attemptId ??= uploaded.attemptId;
        groupId ??= uploaded.locationGroupId ?? uploaded.id;
        if (_disposed) return;
        uploadedCount = i + 1;
        notifyListeners();
      }

      if (_disposed) return;

      // Every photo uploaded — mark the whole attempt completed so it's
      // visible in Earnings. Best-effort: photos are already durably
      // persisted at this point, so a transient failure here must not block
      // the success screen (the manual per-photo stepper remains a fallback).
      // Quick Save never reaches this path — it returns before upload() runs.
      if (attemptId != null) {
        try {
          final statusFuture =
              updateAttemptStatusProvider((attemptId, 'completed')).future;
          await ref.read(statusFuture);
        } catch (e) {
          debugPrint('[upload] failed to mark attempt completed: $e');
        }
      }

      await LocalStorage.clearPinDraft();
      await AttemptSnapshotStore.clear(snapshotId);
      HapticFeedback.heavyImpact();
      uploadState = AttemptUploadState.success;
      lastUploadedPhotoId = lastId;
      locationFrozenFromCache = false;
      notifyListeners();
      refreshProfileWork(ref, profileId: selectedProfile?.id);
      if (attemptId != null) {
        unawaited(_duplicateToLinkedProfiles(context, ref, attemptId));
      }
    } catch (e) {
      debugPrint('[UPLOAD ERROR] $e');
      if (_disposed) return;
      // Field signal dropped (or the server is unreachable). The un-sent
      // photos are already safe in the offline queue (enqueued above) and
      // will upload automatically when connectivity returns — nothing more
      // to persist.
      final queued = watermarked.length - uploadedCount;
      await LocalStorage.clearPinDraft();
      await AttemptSnapshotStore.clear(snapshotId);
      HapticFeedback.heavyImpact();
      uploadState = AttemptUploadState.success;
      locationFrozenFromCache = false;
      notifyListeners();
      refreshProfileWork(ref, profileId: selectedProfile?.id);
      if (context.mounted) {
        showSnack(
          context,
          'Saved offline — $queued photo${queued > 1 ? 's' : ''} will upload '
          'automatically when you have signal.',
        );
      }
    } finally {
      UploadQueueService.instance.resumeAutoProcess();
    }
  }

  void toggleLinkProfile(int id) {
    if (!linkProfileIds.add(id)) linkProfileIds.remove(id);
    notifyListeners();
  }

  /// Blocks logging an attempt unless GPS is within 200 ft of the profile pin.
  /// Creating a profile at a remote pin is allowed; doing the work is not.
  Future<bool> confirmAttemptNearProfile(BuildContext context) async {
    final p = selectedProfile;
    if (p == null || latitude == null || longitude == null) return true;
    if (!LocationService.usableCoordinates(p.latitude, p.longitude)) {
      return true;
    }
    final ft = LocationService.distanceFeet(
      latitude!,
      longitude!,
      p.latitude!,
      p.longitude!,
    );
    if (ft <= kProfileProximityFt) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Too far from this job',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2130),
          ),
        ),
        content: Text(
          'You are ${ft >= 5280 ? '${(ft / 5280).toStringAsFixed(1)} mi' : '${ft.round()} ft'} '
          'from this profile’s location. Log an attempt only when you are within '
          '${kProfileProximityFt.toInt()} feet of the job.',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF5C6778),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A90E2),
              ),
            ),
          ),
        ],
      ),
    );
    return false;
  }

  List<ProfileModel> nearbyLinkProfiles(WidgetRef ref) {
    final selectedId = selectedProfile?.id;
    if (latitude == null || longitude == null) return const [];
    final profiles = ref.read(profilesProvider).valueOrNull ?? const [];
    return [
      for (final p in profiles)
        if (p.id != selectedId &&
            p.latitude != null &&
            p.longitude != null &&
            p.canAddAttempts &&
            const Distance().as(
                  LengthUnit.Meter,
                  LatLng(latitude!, longitude!),
                  LatLng(p.latitude!, p.longitude!),
                ) *
                    3.28084 <=
                kProfileProximityFt)
          p,
    ];
  }

  Future<void> _duplicateToLinkedProfiles(
    BuildContext context,
    WidgetRef ref,
    int attemptId,
  ) async {
    if (_disposed || linkProfileIds.isEmpty) return;
    try {
      final n = await ref.read(profileRepositoryProvider).duplicateAttempt(
            attemptId: attemptId,
            profileIds: linkProfileIds.toList(),
          );
      if (_disposed || !context.mounted) return;
      refreshProfileWork(ref);
      showSnack(
        context,
        'Linked attempt to $n profile${n == 1 ? '' : 's'}',
      );
    } catch (_) {
      if (!_disposed && context.mounted) {
        showSnack(context, 'Could not link profiles', isError: true);
      }
    }
  }

  // ── F1: nearby duplicate detection + existing-pin reuse ───────────────────
  Future<void> checkNearbyAndMaybeReuse(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (nearbyCheckDone || latitude == null || longitude == null) return;
    try {
      final nearby = await ref.read(apiServiceProvider).getNearby(
            latitude: latitude!,
            longitude: longitude!,
            radiusFt: 200, // duplicate-pin detection radius
          );
      if (_disposed || nearby.isEmpty || !context.mounted) return;
      final nearest = nearby.first;
      final distFt = (nearest['distance_ft'] as num?)?.toDouble();
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
      if (_disposed) return;
      if (useExisting ?? false) {
        locationGroupId = nearest['location_group_id'] as int?;
        notifyListeners();
        saveDraft();
      }
    } catch (_) {
      // Best-effort — never block an upload on this.
    } finally {
      if (!_disposed) {
        nearbyCheckDone = true;
        notifyListeners();
      }
    }
  }
}
