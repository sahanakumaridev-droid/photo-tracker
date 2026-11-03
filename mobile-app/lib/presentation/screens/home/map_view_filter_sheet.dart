part of 'map_view_screen.dart';

extension _MapBodyFilterExt on _MapBodyState {
  void _fitToActiveFilter() {
    if (!mounted) return;
    if (_distanceMode == 'distance' && widget.userPosition != null) {
      final lat = widget.userPosition!.latitude;
      final lng = widget.userPosition!.longitude;
      final radiusMi = _distanceMi < 0.5 ? 0.5 : _distanceMi;
      final latDelta = radiusMi / 69.0;
      final cosLat = math.cos(lat * math.pi / 180).abs();
      final lngDelta = radiusMi / (69.0 * (cosLat < 0.01 ? 0.01 : cosLat));
      widget.mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(lat - latDelta, lng - lngDelta),
            LatLng(lat + latDelta, lng + lngDelta),
          ),
          padding: const EdgeInsets.all(60),
        ),
      );
      return;
    }
    widget.onFitAll(_mapJobs().map((j) => j.point).toList());
  }

  void _scheduleFilterFit() {
    _filterFitDebounce?.cancel();
    _filterFitDebounce =
        Timer(const Duration(milliseconds: 300), _fitToActiveFilter);
  }

  bool get _anyFilterActive =>
      _levels.isNotEmpty ||
      _todayOnly ||
      _distanceMode != null ||
      widget.searchCtrl.text.trim().isNotEmpty;

  // Resets every active filter (priority level, today, distance) from
  // outside the filter sheet — used by the "no pins match" empty state so a
  // narrow filter never strands the user without a way back.
  void _clearAllFilters() {
    _rebuild(() {
      _levels.clear();
      _todayOnly = false;
      _distanceMode = null;
      _distanceMi = 100;
      _selectedJob = null;
    });
    widget.searchCtrl.clear();
    _scheduleFilterFit();
  }

  String _categoryDetail(String value) => switch (value) {
        'asap' => 'Rush jobs that need to go out as soon as possible.',
        'special' => 'Jobs that need extra care or special instructions.',
        'standard' => 'Regular service attempts at the usual pace.',
        'next_day' => 'Jobs scheduled for the next business day.',
        'stake_out' => 'Surveillance-style jobs that sit on a location.',
        _ => 'Show matching pins on the map.',
      };

  int _geotaggedCountFor(String? category, {bool todayOnly = false}) {
    final now = DateTime.now();
    return widget.photos.where((p) {
      if (p.latitude == 0 && p.longitude == 0) return false;
      if (category != null && (p.category ?? 'standard') != category) {
        return false;
      }
      if (todayOnly) {
        final ts = p.takenAt ?? p.timestamp;
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts)?.toLocal();
        if (dt == null) return false;
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }
      return true;
    }).length;
  }

  Widget _filterDetailRow({
    required String title,
    required String detail,
    required Color color,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    int? count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(0.23, 1, 0.32, 1),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : _kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : _kSep,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected ? Colors.white : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected ? color : _kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: _kInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? color : _kSubtle,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: selected ? color : _kSep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // A soft grouped section container used inside the filter sheet.
  Widget _sheetCard({required String title, required List<Widget> children}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kSep),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _kInkMuted)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Future<bool> _gpsIsOnSite(
    BuildContext context,
    double jobLat,
    double jobLng, {
    bool notify = true,
  }) async {
    final gps = await LocationService.getFreshFix() ??
        await LocationService.getLastKnownLocation();
    if (!context.mounted) return false;
    if (gps == null) {
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read GPS for this attempt.')),
        );
      }
      return false;
    }
    final err = LocationService.attemptTooFarMessage(
      gpsLat: gps.latitude,
      gpsLng: gps.longitude,
      jobLat: jobLat,
      jobLng: jobLng,
      gpsAccuracyMeters: gps.accuracy,
    );
    if (err != null) {
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
      return false;
    }
    return true;
  }

  Future<void> _openAttemptFromGps(double lat, double lng) async {
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    ProfileModel? nearest;
    var nearestFt = LocationService.kAttemptProximityFt;
    for (final p in profiles) {
      if (!p.hasLocation) continue;
      final d = LocationService.distanceFeet(lat, lng, p.latitude!, p.longitude!);
      if (d <= nearestFt) {
        nearestFt = d;
        nearest = p;
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: nearest?.id,
          initialProfile: nearest,
        ),
      ),
    );
    widget.onRefresh();
  }

  void _openHotRouteBubbles(LatLng latLng) {
    if (!LocationService.isInUnitedStates(latLng.latitude, latLng.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hot routes can only be added in the United States.'),
        ),
      );
      return;
    }
    _userPinnedCamera = true;
    _rebuild(() {
      _selectedJob = null;
      _hotRouteAt = latLng;
    });
    // One nudge only. Repeating it sends the pin away from the tap.
    // A corner tap needs the point pulled in just far enough for the menu.
    final generation = ++_hotRouteShiftGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _hotRouteShiftGen) return;
      final camera = widget.mapController.camera;
      final screen = camera.latLngToScreenPoint(latLng);
      final size = camera.size;
      const marginX = 150.0;
      const marginTop = 190.0;
      const marginBottom = 200.0;
      if (size.x < 32 || size.y < 32) return;
      final targetX =
          screen.x.clamp(marginX, math.max(marginX, size.x - marginX));
      final targetY = screen.y.clamp(
        marginTop,
        math.max(marginTop, size.y - marginBottom),
      );
      final dx = screen.x - targetX;
      final dy = screen.y - targetY;
      if (dx.abs() <= 2 && dy.abs() <= 2) return;
      final centerPx = camera.latLngToScreenPoint(camera.center);
      final shifted = camera.pointToLatLng(
        math.Point(centerPx.x + dx, centerPx.y + dy),
      );
      widget.mapController.move(shifted, camera.zoom);
    });
  }

  bool _attemptInRange(LatLng pin) {
    final gps = widget.userPosition;
    if (gps == null) return false;
    return LocationService.distanceFeet(
          gps.latitude,
          gps.longitude,
          pin.latitude,
          pin.longitude,
        ) <=
        LocationService.kAttemptProximityFt;
  }

  Offset _screenOffsetFor(LatLng latLng) {
    try {
      final p = widget.mapController.camera.latLngToScreenPoint(latLng);
      return Offset(p.x, p.y);
    } catch (_) {
      return Offset.zero;
    }
  }

  Future<void> _openAttemptForProfile(ProfileModel created) async {
    widget.onRefresh();
    if (!mounted || created.id == 0) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: created.id,
          initialProfile: created,
        ),
      ),
    );
  }

  Future<void> _onHotRouteChoice(String choice, LatLng latLng) async {
    _rebuild(() => _hotRouteAt = null);
    if (choice == 'hot') {
      if (!LocationService.isInUnitedStates(
          latLng.latitude, latLng.longitude)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A hot route can only be created in the United States.'),
          ),
        );
        return;
      }
      String? address;
      try {
        address = await LocationService.reverseGeocode(
          latLng.latitude,
          latLng.longitude,
        );
      } catch (_) {}
      if (!context.mounted) return;
      final created = await showCreateProfileDialog(
        context,
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        address: address,
        hotRoute: true,
      );
      if (created != null) {
        final pinLat = created.latitude ?? latLng.latitude;
        final pinLng = created.longitude ?? latLng.longitude;
        _focusProfileId = created.id;
        widget.onRefresh();
        widget.mapController.move(LatLng(pinLat, pinLng), 17);
      }
      return;
    }
    if (choice == 'attempt') {
      final gps = widget.userPosition;
      if (gps == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on location to add an attempt.')),
        );
        return;
      }
      _rebuild(() => _glowNearby = true);
      _pullCameraToRadius();
      var eligible = 0;
      var completeNearby = false;
      for (final job in _mapJobs()) {
        if (!job.hasPoint || job.profile == null) continue;
        if (!_inAttemptRange(job)) continue;
        if (!_jobAcceptsAttempt(job)) {
          completeNearby = true;
          continue;
        }
        eligible++;
      }
      if (eligible == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completeNearby
                  ? 'Nearby green pins are already complete. Use a yellow or orange pin within 500 ft.'
                  : 'Move within 500 feet of a profile, then tap Attempt again.',
            ),
          ),
        );
      }
      return;
    }
    if (choice == 'camera') {
      try {
        await ImagePicker().pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
          preferredCameraDevice: CameraDevice.rear,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the camera.')),
          );
        }
      }
      return;
    }
    if (choice == 'mileage') {
      final container = ProviderScope.containerOf(context);
      final dio = container.read(dioProvider);
      final email = container.read(authProvider).email;
      await MileageTracker.instance.toggle(dio, email: email);
    }
  }

  // Filter sheet: same dock categories (with details) plus distance.
  void _showFilterSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, ssheet) {
          // Runs the mutation exactly once, then rebuilds both the sheet and
          // the map behind it. Must NOT call fn() twice — toggles like the
          // priority-level bubbles (add-if-absent / remove-if-present) would
          // cancel themselves out on the second call.
          void refresh(VoidCallback fn) {
            fn();
            ssheet(() {});
            _rebuild(() {}); // rebuild the map behind the sheet
          }

          final hasLoc = widget.userPosition != null;
          final anyActive =
              _levels.isNotEmpty || _todayOnly || _distanceMode != null;
          final resultCount = _mapJobs().length;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF2F4F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded,
                          size: 20, color: _kAccent),
                      const SizedBox(width: 8),
                      const Text('Filter pins',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kInk)),
                      const Spacer(),
                      if (anyActive)
                        TextButton(
                          onPressed: () {
                            refresh(() {
                              _levels.clear();
                              _todayOnly = false;
                              _distanceMode = null;
                              _distanceMi = 100;
                            });
                            _scheduleFilterFit();
                          },
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetCard(
                          title: 'When',
                          children: [
                            _filterDetailRow(
                              title: 'Today',
                              detail: 'Only pins captured today.',
                              color: _kAccent,
                              icon: Icons.calendar_today_rounded,
                              selected: _todayOnly,
                              count: _geotaggedCountFor(null, todayOnly: true),
                              onTap: () =>
                                  refresh(() => _todayOnly = !_todayOnly),
                            ),
                          ],
                        ),
                        // ── Distance ──
                        _sheetCard(
                          title: 'Distance',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Within my range',
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: _distanceMode == 'distance'
                                              ? _kInk
                                              : _kInkMuted)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _distanceMode == 'distance'
                                        ? _kAccent
                                        : _kAccent.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('${_distanceMi.round()} mi',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _distanceMode == 'distance'
                                              ? Colors.white
                                              : _kAccent)),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(sheetCtx).copyWith(
                                trackHeight: 4,
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16),
                              ),
                              child: Slider(
                                value: _distanceMi,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                activeColor: _kAccent,
                                inactiveColor:
                                    _kAccent.withValues(alpha: 0.15),
                                onChanged: hasLoc
                                    ? (v) {
                                        refresh(() {
                                          _distanceMi = v;
                                          _distanceMode = 'distance';
                                        });
                                        _scheduleFilterFit();
                                      }
                                    : null,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('0 mi',
                                      style: TextStyle(
                                          fontSize: 11, color: _kInkMuted)),
                                  Text('100 mi',
                                      style: TextStyle(
                                          fontSize: 11, color: _kInkMuted)),
                                ],
                              ),
                            ),
                            if (!hasLoc)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                    'Enable GPS to filter by distance.',
                                    style: TextStyle(
                                        fontSize: 12, color: _kAsap)),
                                ),
                            if (_distanceMode != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                      padding: const EdgeInsets.only(top: 8),
                                      foregroundColor: _kInkMuted,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () {
                                    refresh(() {
                                      _distanceMode = null;
                                    });
                                    _scheduleFilterFit();
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      size: 15),
                                  label: const Text('Clear distance filter'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Sticky footer: apply / show results ──
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 12, 20, MediaQuery.of(sheetCtx).padding.bottom + 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _kSep)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                          resultCount == 0
                              ? 'No pins match'
                              : 'Show $resultCount '
                                  'pin${resultCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Marker _jobMarker(_MapJob job, List<_MapJob> all) {
    // Pins with attempts stay yellow (or green if complete) even when tapped.
    // Only first-time orange pins use the selected/map-card highlight.
    final selected = !job.hasAttempts && _isSelectedJob(job);
    final glow =
        _glowNearby && _inAttemptRange(job) && _jobAcceptsAttempt(job);
    return Marker(
      point: _spreadPoint(job, all),
      width: glow ? 56 : 48,
      height: glow ? 68 : 58,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          unawaited(_openJobFromPin(job));
        },
        child: _PinMarker(
          color: job.pinColor,
          selected: selected,
          glow: glow,
          label: null,
        ),
      ),
    );
  }

  /// Prefer a pin tap over the empty-map hot-wheel. Stacked jobs sit on the
  /// GPS puck, so flutter_map often delivers the tap to the map instead.
}
