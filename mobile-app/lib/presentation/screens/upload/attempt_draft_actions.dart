part of 'attempt_draft_controller.dart';

extension AttemptDraftActionsExt on AttemptDraftController {
  Future<void> pickImage(BuildContext context, ImageSource source) async {
    HapticFeedback.lightImpact();
    if (source == ImageSource.camera) {
      await pickFromCamera(context);
    } else {
      await pickFromGallery(context);
    }
  }

  Future<void> pickFromCamera(BuildContext context) async {
    // Do not call Permission.camera.request(). ImagePicker shows the system
    // prompt once. Asking again here is what feels like continual access.
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
        backgroundColor: isError
            ? AttemptDraftController.errorRed
            : AttemptDraftController.successGreen,
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
  void bump() => notifyListeners();

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
    companyId = companyById(p.company)?.id ?? companyId;
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
    if (!AttemptDraftController.servedToNeedsRelation(value)) {
      relationToController.clear();
    }
  }

  Future<void> addCustomServedToName(String name, {String? gender}) async {
    await LocalStorage.addServedToCustomName(name, gender: gender);
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

  /// Profiles whose saved address is within [kProfileFilterFt] of this job.
  /// The selected profile's address is the anchor. The phone GPS is used
  /// only before a profile is chosen.
  Set<int> nearbyProfileIds(WidgetRef ref) {
    final originLat = selectedProfile?.latitude ?? latitude;
    final originLng = selectedProfile?.longitude ?? longitude;
    if (originLat == null || originLng == null) return {};
    final profiles = ref.read(profilesProvider).valueOrNull ?? const [];
    final ids = <int>{};
    for (final p in profiles) {
      if (p.latitude == null || p.longitude == null) continue;
      final km = LocationService.calculateDistance(
          originLat, originLng, p.latitude!, p.longitude!);
      if (km * 3280.84 <= AttemptDraftController.kProfileFilterFt) {
        ids.add(p.id);
      }
    }
    return ids;
  }

  /// Served To choices: the fixed presets, then names of other profiles
  /// whose address is within [kProfileFilterFt]. Old custom names saved on
  /// the phone are not listed.
  List<String> servedToChoices(WidgetRef ref) {
    final names = <String>[...AttemptDraftController.kServedToPresets];
    final nearby = nearbyProfileIds(ref);
    final profiles = ref.read(profilesProvider).valueOrNull ?? const [];
    for (final p in profiles) {
      if (!nearby.contains(p.id)) continue;
      if (p.id == selectedProfile?.id) continue;
      final name = p.name.trim();
      if (name.isEmpty || names.contains(name)) continue;
      names.add(name);
    }
    return names;
  }

  // ── Upload ──────────────────────────────────────────────────────────────
  Future<void> upload(BuildContext context, WidgetRef ref) async {
    // Guard: prevent duplicate submissions. Set this before any await so a
    // second tap cannot start another attempt while GPS or upload is running.
    if (uploadState == AttemptUploadState.uploading ||
        uploadState == AttemptUploadState.processing) {
      return;
    }
    uploadState = AttemptUploadState.uploading;
    notifyListeners();

    if (selectedImages.isEmpty) {
      uploadState = AttemptUploadState.idle;
      notifyListeners();
      showSnack(context, 'Please select at least one photo', isError: true);
      return;
    }
    if (selectedProfile == null) {
      uploadState = AttemptUploadState.idle;
      notifyListeners();
      showSnack(context, 'Please select a profile', isError: true);
      return;
    }
    if (!selectedProfile!.canAddAttempts) {
      uploadState = AttemptUploadState.idle;
      notifyListeners();
      showSnack(
        context,
        'This profile is completed and cannot receive new attempts.',
        isError: true,
      );
      return;
    }
    if (latitude == null || longitude == null) {
      uploadState = AttemptUploadState.idle;
      notifyListeners();
      showSnack(context, 'Location required. Tap Refresh to retry.',
          isError: true);
      return;
    }
    if (!await confirmAttemptNearProfile(context, ref)) {
      uploadState = AttemptUploadState.idle;
      notifyListeners();
      return;
    }

    final servedToValue = servedToController.text.trim();
    if (isSuccessfulAttempt &&
        servedToValue.isNotEmpty &&
        AttemptDraftController.servedToNeedsRelation(servedToValue) &&
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
    uploadedCount = 0;
    notifyListeners();

    final rawPayRate = int.tryParse(payRateController.text.trim());
    final payRate =
        (rawPayRate != null && rawPayRate > 0) ? rawPayRate : null;
    final address = addressController.text.trim().isEmpty
        ? null
        : addressController.text.trim();
    final noteBody = noteController.text.trim();
    final desc = isSuccessfulAttempt && !subjectDescription.isEmpty
        ? subjectDescription.toNoteBlock()
        : '';
    final note = [
      if (noteBody.isNotEmpty) noteBody,
      if (desc.isNotEmpty) desc,
    ].join('\n');
    final noteOrNull = note.isEmpty ? null : note;
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
    final batchId = 'batch-${DateTime.now().microsecondsSinceEpoch}';
    for (var i = 0; i < watermarked.length; i++) {
      final q = await UploadQueueService.instance.enqueue(
        sourceFile: watermarked[i],
        profileId: selectedProfile!.id,
        latitude: latitude!,
        longitude: longitude!,
        takenAt: takenAts[i] ?? DateTime.now().toUtc().toIso8601String(),
        address: address,
        note: noteOrNull,
        category: selectedProfile?.serviceType ?? selectedCategory,
        completionType: completionType,
        servedTo: servedTo,
        relationTo: relationTo,
        fileNumber: fileNumber,
        successful: isSuccessfulAttempt,
        attemptStatus: attemptStatus,
        payRate: payRate,
        locationGroupId: locationGroupId,
        profileName: selectedProfile!.name,
        batchId: batchId,
        serverAttemptId: existingAttemptId,
        drain: false,
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
          'clientBatchId': batchId,
          'completionType': completionType,
          'note': note,
          'category': selectedProfile?.serviceType ?? selectedCategory,
          'payRate': payRate,
          'takenAt': takenAts[i],
          'locationGroupId': groupId,
        }).future);
        // Sent — drop it from the queue so the drainer can't re-send it.
        await UploadQueueService.instance.remove(queueIds[i]);
        lastId = uploaded.id;
        attemptId ??= uploaded.attemptId;
        if (attemptId != null) {
          await UploadQueueService.instance
              .attachAttemptToBatch(batchId, attemptId);
        }
        groupId ??= uploaded.locationGroupId ?? uploaded.id;
        if (_disposed) return;
        uploadedCount = i + 1;
        notifyListeners();
      }

      if (_disposed) return;

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
      final msg = e.toString();
      final blocked = msg.contains('United States') ||
          msg.contains('500 feet') ||
          msg.contains('within 500') ||
          msg.contains('from this job');
      if (blocked) {
        for (final id in queueIds) {
          await UploadQueueService.instance.remove(id);
        }
        uploadState = AttemptUploadState.idle;
        notifyListeners();
        if (context.mounted) {
          showSnack(
            context,
            'Attempt not saved. You can only send from the United States.',
            isError: true,
          );
        }
        return;
      }
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

  /// Blocks logging an attempt outside the United States.
  Future<bool> confirmAttemptNearProfile(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final p = selectedProfile;
    if (p == null) return true;
    Position? gps;
    try {
      gps = await LocationService.getFreshFix();
    } catch (_) {}
    if (gps == null) {
      if (context.mounted) {
        showSnack(
          context,
          'GPS is required to log an attempt. Enable location and try again.',
          isError: true,
        );
      }
      return false;
    }
    latitude = gps.latitude;
    longitude = gps.longitude;
    gpsAccuracy = gps.accuracy;
    final here = await LocationService.reverseGeocode(
      gps.latitude,
      gps.longitude,
    );
    if (here != null && here.trim().isNotEmpty) {
      addressController.text = here.trim();
    }
    notifyListeners();
    final missingPin = p.latitude == null || p.longitude == null;
    if (missingPin) {
      try {
        await ref.read(updateProfileProvider((
          profileId: p.id,
          name: p.name,
          serviceType: p.serviceType,
          company: p.company,
          note: p.note,
          payRate: p.payRate,
          deliveryStyle: p.deliveryStyle,
          status: p.status,
          address: addressController.text.trim().isEmpty
              ? p.address
              : addressController.text.trim(),
          city: p.city,
          state: p.state,
          postalCode: p.postalCode,
          latitude: gps.latitude,
          longitude: gps.longitude,
        )).future);
        selectedProfile = p.copyWith(
          latitude: gps.latitude,
          longitude: gps.longitude,
          address: addressController.text.trim().isEmpty
              ? p.address
              : addressController.text.trim(),
        );
        refreshProfileWork(ref, profileId: p.id);
      } catch (_) {}
      return true;
    }
    final tooFar = LocationService.attemptTooFarMessage(
      gpsLat: gps.latitude,
      gpsLng: gps.longitude,
      jobLat: p.latitude,
      jobLng: p.longitude,
      gpsAccuracyMeters: gps.accuracy,
    );
    if (tooFar == null) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Can’t log this attempt',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2130),
          ),
        ),
        content: Text(
          tooFar,
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
                AttemptDraftController.kProfileProximityFt)
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
    // The profile was already chosen from the map. Do not ask to attach
    // the attempt to a nearby pin.
    if (initialProfileId != null || selectedProfile != null) {
      nearbyCheckDone = true;
      return;
    }
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
