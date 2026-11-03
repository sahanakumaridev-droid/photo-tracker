part of 'map_view_screen.dart';

extension _MapBodyJobsExt on _MapBodyState {
  _MapJob? _jobNearTap(LatLng tap, List<_MapJob> jobs) {
    final tapPx = _screenOffsetFor(tap);
    if (tapPx == Offset.zero && jobs.isEmpty) return null;
    _MapJob? best;
    var bestPx = 56.0;
    for (final job in jobs) {
      if (!job.hasPoint) continue;
      final pinPx = _screenOffsetFor(_spreadPoint(job, jobs));
      final d = (pinPx - tapPx).distance;
      if (d < bestPx) {
        bestPx = d;
        best = job;
      }
    }
    return best;
  }

  bool _inAttemptRange(_MapJob job) {
    final gps = widget.userPosition;
    if (gps == null || !job.hasPoint) return false;
    return LocationService.distanceFeet(
          gps.latitude,
          gps.longitude,
          job.lat,
          job.lng,
        ) <=
        LocationService.kAttemptProximityFt;
  }

  /// Green / completed / archived pins cannot take a new attempt.
  bool _jobAcceptsAttempt(_MapJob job) {
    if (job.diligenceComplete) return false;
    final profile = job.profile;
    if (profile != null && !profile.canAddAttempts) return false;
    return true;
  }

  void _pullCameraToRadius() {
    final gps = widget.userPosition;
    if (gps == null) return;
    const meters = 152.4;
    const dLat = meters / 111320;
    final dLng =
        meters / (111320 * math.cos(gps.latitude * math.pi / 180).abs());
    _userPinnedCamera = true;
    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(gps.latitude - dLat, gps.longitude - dLng),
          LatLng(gps.latitude + dLat, gps.longitude + dLng),
        ),
        padding: const EdgeInsets.fromLTRB(36, 150, 36, 160),
        maxZoom: 18,
      ),
    );
    if (mounted) _rebuild(() {});
  }

  /// Fan coincident pins into a ring so 10 jobs at one GPS still all show.
  LatLng _spreadPoint(_MapJob job, List<_MapJob> all) {
    final twins = all
        .where((j) =>
            (j.lat - job.lat).abs() < 1e-4 && (j.lng - job.lng).abs() < 1e-4)
        .toList();
    if (twins.length <= 1) return job.point;
    final i = twins.indexOf(job);
    final n = twins.length;
    final angle = (2 * math.pi * (i < 0 ? 0 : i)) / n;
    // ~20 m base so stacked jobs stay near the real address (the old 250 m
    // ring put the pin outside the 500 ft attempt radius).
    final d = 0.00032 + n * 0.00005;
    return LatLng(
      job.lat + d * math.cos(angle),
      job.lng + d * math.sin(angle),
    );
  }

  bool _isSelectedJob(_MapJob job) {
    final s = _selectedJob;
    if (s == null) return false;
    if (s.profile != null && job.profile != null) {
      return s.profile!.id == job.profile!.id;
    }
    return s.jobId == job.jobId;
  }

  PhotoModel? _photoForJob(_MapJob job) {
    if (job.photos.isNotEmpty) return job.photos.first;
    final pid = job.profile?.id ?? job.latest?.profileId;
    if (pid == null || pid == 0) return job.latest;
    final all = ref.read(photosProvider).valueOrNull ?? const <PhotoModel>[];
    final matches = all
        .where((ph) =>
            ph.profileId == pid ||
            (ph.profiles?.any((p) => p.id == pid) ?? false))
        .toList()
      ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _openJobFromPin(_MapJob job) async {
    if (!mounted) return;
    // Attempt on the hot wheel: only glowing pins within 500 ft open
    // Add Attempt. Regular pin taps still go to the photo screen.
    if (_glowNearby) {
      if (_inAttemptRange(job) && _jobAcceptsAttempt(job)) {
        await _startAttemptFromPin(context, job: job);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pick a glowing pin within 500 feet to add an attempt.',
          ),
        ),
      );
      return;
    }
    final photo = _photoForJob(job);
    final pid = job.profile?.id ??
        job.latest?.profileId ??
        photo?.profileId;
    // Yellow / green pins with an attempt open the attempt photo screen,
    // not the Service Attempts list.
    if (job.hasAttempts) {
      var photoId = (photo != null && photo.id != 0) ? photo.id : 0;
      if (photoId == 0 && pid != null && pid != 0) {
        final attempts =
            ref.read(profileAttemptsProvider(pid)).valueOrNull;
        if (attempts != null && attempts.isNotEmpty) {
          photoId = attempts.first.photoId;
        }
      }
      if (photoId != 0) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoDetailScreen(photoId: photoId),
          ),
        );
        return;
      }
      _rebuild(() => _selectedJob = job);
      return;
    }
    _rebuild(() => _selectedJob = job);
  }

  Future<void> _startAttemptFromPin(BuildContext context, {_MapJob? job}) async {
    final selected = job ?? _selectedJob;
    if (selected == null) return;
    final pid = selected.profile?.id ?? selected.latest?.profileId;
    if (pid == null || pid == 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open this job from Profiles, or create a profile first.',
          ),
        ),
      );
      return;
    }
    final gps = widget.userPosition;
    if (gps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on location to add an attempt.')),
      );
      return;
    }
    final feet = LocationService.distanceFeet(
      gps.latitude,
      gps.longitude,
      selected.lat,
      selected.lng,
    );
    if (feet > LocationService.kAttemptProximityFt) {
      _rebuild(() => _glowNearby = true);
      _pullCameraToRadius();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You are ${feet.round()} ft from this pin. An attempt is only allowed within 500 feet, and it uses your current location.',
          ),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final ok = await ensureCanStartNewAttempt(
      context,
      ref,
      profileId: pid,
      knownCount: selected.attemptCount,
    );
    if (!ok || !context.mounted) return;
    if (mounted) _rebuild(() => _glowNearby = false);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: pid,
          initialProfile: selected.profile,
        ),
      ),
    );
  }

  String _latestJobLabel(List<_MapJob> jobs) {
    _MapJob? latest;
    for (final job in jobs) {
      if (latest == null) {
        latest = job;
        continue;
      }
      final stamp = job.latest?.timestamp ?? '';
      final other = latest.latest?.timestamp ?? '';
      if (stamp.compareTo(other) > 0) {
        latest = job;
      } else if (stamp == other &&
          (job.profile?.id ?? 0) > (latest.profile?.id ?? 0)) {
        latest = job;
      }
    }
    if (latest == null) return 'No recent profile';
    final hot = (latest.profile?.deliveryStyle ?? '').trim().isEmpty &&
        latest.profile != null;
    return hot ? '${latest.recipient}\nHot route' : latest.recipient;
  }

  String? _distanceLabelFor(double lat, double lng) {
    final pos = widget.userPosition;
    if (pos == null) return null;
    final m = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, lat, lng);
    final mi = m / 1609.34;
    if (mi < 0.1) return 'Nearby';
    return '${mi.toStringAsFixed(1)} mi';
  }

  String _addressOf(PhotoModel p) {
    final addr = p.address?.trim();
    if (addr != null && addr.isNotEmpty) return addr;
    final zip = p.zipCode?.trim();
    if (zip != null && zip.isNotEmpty) return 'ZIP $zip';
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  // The photos visible on the map after all active filters (service level,
  // distance) + a valid geotag. Shared by build() and the filter sheet's
  // live result count.
  List<PhotoModel> _visiblePhotos() {
    var filtered = widget.photos;

    if (_levels.isNotEmpty) {
      filtered = filtered
          .where((p) => _levels.contains(p.category ?? 'standard'))
          .toList();
    }

    if (_todayOnly) {
      final now = DateTime.now();
      filtered = filtered.where((p) {
        final ts = p.takenAt ?? p.timestamp;
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts)?.toLocal();
        if (dt == null) return false;
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }).toList();
    }

    // Distance filter.
    if (_distanceMode == 'distance' && widget.userPosition != null) {
      final ulat = widget.userPosition!.latitude;
      final ulng = widget.userPosition!.longitude;
      filtered = filtered.where((p) {
        final km = LocationService.calculateDistance(
            ulat, ulng, p.latitude, p.longitude);
        return km * 0.621371 <= _distanceMi; // km → miles
      }).toList();
    }

    if (widget.searchCtrl.text.trim().isNotEmpty) {
      filtered = filtered.where((p) {
        return _matchesProfileOrZip(
          name: p.profileName,
          zip: p.zipCode,
          address: p.address,
        );
      }).toList();
    }

    return filtered
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
  }

  /// Same job grouping as the Jobs tab: one pin per profile, plus leftover
  /// geotagged photos that have no profile. Pending / awaiting jobs stay on
  /// the map as yellow pins.
  List<_MapJob> _mapJobs() {
    final photos = _visiblePhotos();
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    final used = <int>{};
    final jobs = <_MapJob>[];

    for (final profile in profiles) {
      final pPhotos = photos
          .where((ph) =>
              ph.profileId == profile.id ||
              (ph.profiles?.any((p) => p.id == profile.id) ?? false))
          .toList()
        ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      for (final p in pPhotos) {
        used.add(p.id);
      }
      if (pPhotos.isEmpty) {
        if (_todayOnly) continue;
        if (_levels.isNotEmpty &&
            !_levels.contains(profile.serviceType.toLowerCase())) {
          continue;
        }
        if (!profile.hasLocation) continue;
        if (!_profilePassesDistanceAndSearch(profile)) continue;
      }
      final job = _MapJob(profile: profile, photos: pPhotos);
      if (job.hasPoint &&
          LocationService.isInUnitedStates(job.lat, job.lng)) {
        jobs.add(job);
      }
    }

    final leftover = photos.where((p) => !used.contains(p.id)).toList();
    for (final g in _groupByLocation(leftover).values) {
      g.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      final job = _MapJob(profile: null, photos: g);
      if (job.hasPoint &&
          LocationService.isInUnitedStates(job.lat, job.lng)) {
        jobs.add(job);
      }
    }
    return jobs;
  }

  bool _profilePassesDistanceAndSearch(ProfileModel profile) {
    if (_distanceMode == 'distance' && widget.userPosition != null &&
        profile.hasLocation) {
      final km = LocationService.calculateDistance(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        profile.latitude!,
        profile.longitude!,
      );
      if (km * 0.621371 > _distanceMi) return false;
    }
    return _matchesProfileOrZip(
      name: profile.name,
      zip: profile.postalCode,
      address: profile.address,
    );
  }

  bool _matchesProfileOrZip({
    String? name,
    String? zip,
    String? address,
  }) {
    final q = widget.searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    if ((name ?? '').toLowerCase().contains(q)) return true;
    if ((zip ?? '').toLowerCase().contains(q)) return true;
    if (RegExp(r'^\d{5}').hasMatch(q) && (address ?? '').contains(q)) {
      return true;
    }
    return false;
  }

  Widget _nextUpChip(List<_MapJob> jobs) {
    final open = [
      for (final j in jobs)
        if (j.profile == null || j.profile!.canAddAttempts) j,
    ];
    if (open.isEmpty) return const SizedBox.shrink();

    const sd = LatLng(32.7157, -117.1611);
    final pos = widget.userPosition;
    final originLat = pos?.latitude ?? sd.latitude;
    final originLng = pos?.longitude ?? sd.longitude;

    _MapJob next = open.first;
    var best = double.infinity;
    for (final j in open) {
      if (!j.hasPoint) continue;
      final d = Geolocator.distanceBetween(
        originLat, originLng, j.lat, j.lng,
      );
      if (d < best) {
        best = d;
        next = j;
      }
    }

    final name = next.recipient;
    double? miles;
    if (next.hasPoint) {
      miles = best.isFinite ? best / 1609.34 : null;
    }

    final dist = miles == null
        ? null
        : miles < 0.1
            ? 'Nearby'
            : miles < 10
                ? '${miles.toStringAsFixed(1)} mi'
                : '${miles.round()} mi';
    final pay = next.profile?.payRate;
    final jobLine = (next.profile?.displayCompanyName ?? next.address).trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          unawaited(_openJobFromPin(next));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: _kAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        'Next up',
                        name,
                        if (dist != null) dist,
                        if (pay != null) '\$$pay',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                    if (miles != null || jobLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (miles != null)
                            miles < 0.1
                                ? 'Nearby'
                                : '${miles.toStringAsFixed(1)} mi away',
                          if (jobLine.isNotEmpty) jobLine,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kInkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: _kSubtle),
            ],
          ),
        ),
      ),
    );
  }

}
