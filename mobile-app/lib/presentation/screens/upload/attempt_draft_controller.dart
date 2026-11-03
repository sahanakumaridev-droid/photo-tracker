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
import '../../../core/utils/note_phrases.dart';
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
part 'attempt_draft_actions.dart';

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
  static const double kProfileProximityFt = 500;

  /// Profile picker: every profile whose saved address is within this distance.
  static const double kProfileFilterFt = 300;

  static const int kMaxAttemptsPerJob = 6;

  static const List<String> kServedToPresets = [
    'Same as Profile',
    'John Doe',
    'Jane Doe',
    'Posted to Door',
  ];

  /// These choices are not a person's name, so Relation To stays hidden.
  static bool servedToNeedsRelation(String value) {
    final v = value.trim().toLowerCase();
    return v.isNotEmpty &&
        v != 'same as profile' &&
        v != 'posted to door';
  }

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
  final subjectDescription = SubjectDescription();

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
    if (_disposed || snapshot == null || !_mapHasWork(snapshot)) return;
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
    if (!_draftHasWork) {
      unawaited(LocalStorage.clearPinDraft());
      return;
    }
    LocalStorage.savePinDraft(jsonEncode({
      ...attemptPayload(source: 'draft'),
      'photoPaths': selectedImages.map((f) => f.path).toList(),
    }));
    // While signal is poor, keep the durable frozen snapshot fresh too.
    if (poorNetwork) {
      unawaited(writeAttemptSnapshot(source: 'poor_network_auto'));
    }
  }

  bool get _draftHasWork =>
      selectedImages.isNotEmpty ||
      noteController.text.trim().isNotEmpty ||
      servedToController.text.trim().isNotEmpty;

  bool _mapHasWork(Map<String, dynamic> draft) {
    final photos = draft['photoPaths'];
    final photoCount = photos is List ? photos.length : 0;
    final note = (draft['note'] as String?)?.trim() ?? '';
    final served = (draft['servedTo'] as String?)?.trim() ?? '';
    return photoCount > 0 || note.isNotEmpty || served.isNotEmpty;
  }

  Future<void> maybeRestoreDraft(BuildContext context, WidgetRef ref) async {
    final raw = LocalStorage.getPinDraft();
    if (raw == null || _disposed || !context.mounted) return;
    Map<String, dynamic> draft;
    try {
      draft = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await LocalStorage.clearPinDraft();
      return;
    }
    if (!_mapHasWork(draft)) {
      await LocalStorage.clearPinDraft();
      return;
    }
    // A new or chosen profile starts a fresh attempt. An older draft
    // belongs to other work and must not interrupt this one.
    if (initialProfileId != null) return;
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
        p.payRate! > 0 &&
        (force || payRateController.text.trim().isEmpty)) {
      payRateController.text = '${p.payRate}';
    }
    final standingFn = (p.fileNumber ?? '').trim();
    if (standingFn.isNotEmpty &&
        (force || fileNumberController.text.trim().isEmpty)) {
      fileNumberController.text = standingFn;
    }
    // The profile address is only free-typed on a hot route. An attempt
    // never inherits it — the attempt address is the user's GPS geotag.
  }

  /// Records GPS at the moment a photo is captured so the attempt tag
  /// matches the shutter, not a later form-open location.
  Future<void> _stampGeotagAtCapture() async {
    if (locationFrozenFromCache && latitude != null) return;
    try {
      final pos = await LocationService.getFreshFix();
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
      if (!_disposed && address != null && address.isNotEmpty) {
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
    if (context.mounted) {
      showSnack(
        context,
        'Attempt location is locked to your GPS geotag and cannot be changed.',
        isError: true,
      );
    }
  }

  // ── Camera / Gallery ────────────────────────────────────────────────────
}
