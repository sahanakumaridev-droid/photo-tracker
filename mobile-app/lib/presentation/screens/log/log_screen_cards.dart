part of 'log_screen_v2.dart';

extension _LogScreenCardsExt on _LogScreenV2State {
  Future<void> _startAttemptForProfile(
    ProfileModel? profile,
    LogEntryModel log,
  ) async {
    final pid = profile?.id ?? log.profileId;
    if (pid == null || pid <= 0) return;
    HapticFeedback.mediumImpact();
    final ok = await ensureCanStartNewAttempt(
      context,
      ref,
      profileId: pid,
      knownCount: profile?.attemptsCount,
    );
    if (!ok || !mounted) return;
    await context.push(
      '/new-attempt?profileId=$pid',
      extra: profile,
    );
    if (!mounted) return;
    ref.invalidate(logProvider(_filters));
    ref.invalidate(profilesProvider);
    ref.invalidate(photosProvider);
  }

  // ── Log card ──────────────────────────────────────────────────────────────
  Widget _buildLogCard(LogEntryModel log, int index, [dynamic userPos]) {
    // Priority reflects the per-photo category (the profile serviceType is a
    // legacy field and is now always 'standard' — see the Category badge).
    final cat = categoryOf(log.category);

    final ProfileModel? nested = (log.profiles != null && log.profiles!.isNotEmpty)
        ? log.profiles!.first
        : null;
    ProfileModel? catalogMatch;
    final pid = log.profileId ?? nested?.id;
    if (pid != null) {
      for (final p in ref.watch(profilesProvider).valueOrNull ?? const []) {
        if (p.id == pid) {
          catalogMatch = p;
          break;
        }
      }
    }
    final profile = catalogMatch ?? nested;

    String? distLabel;
    double? distFeet;
    final pinLat = (log.latitude.abs() > 0.0001 || log.longitude.abs() > 0.0001)
        ? log.latitude
        : (profile?.latitude ?? 0.0);
    final pinLng = (log.latitude.abs() > 0.0001 || log.longitude.abs() > 0.0001)
        ? log.longitude
        : (profile?.longitude ?? 0.0);
    final hasPin = pinLat.abs() > 0.0001 || pinLng.abs() > 0.0001;
    if (userPos != null && hasPin) {
      distFeet = LocationService.distanceFeet(
        userPos.latitude,
        userPos.longitude,
        pinLat,
        pinLng,
      );
      final km = LocationService.calculateDistance(
        userPos.latitude, userPos.longitude,
        pinLat, pinLng,
      );
      final mi = km * 0.621371;
      if (mi < 0.1) {
        distLabel = 'Nearby';
      } else if (mi < 10) {
        distLabel = '${mi.toStringAsFixed(1)} miles away';
      } else {
        distLabel = '${mi.round()} miles away';
      }
    }
    final hasPhoto = log.imageUrl.trim().isNotEmpty;
    final imageUrl = hasPhoto ? '${AppConfig.apiBaseUrl}${log.imageUrl}' : '';
    final selected = _selectedLogIds.contains(log.id);
    final unsuccessful =
        normalizeAttemptStatus(log.attemptStatus) == kAttemptStatusUnsuccessful;
    final companyName = profile?.displayCompanyName;
    final attemptCount = profile?.attemptsCount ?? (log.id > 0 ? 1 : 0);
    final attemptCap = attemptCapForProfile(profile);
    final attemptLabel =
        attemptCount == 0 ? 'No attempt' : '$attemptCount of $attemptCap';
    final withinRange = !hasPin ||
        (distFeet != null && distFeet <= LocationService.kAttemptProximityFt);
    final canAddAttempt = pid != null &&
        pid > 0 &&
        (profile == null || profile.canAddAttempts) &&
        attemptCount < attemptCap &&
        withinRange;
    final payRate = (profile?.payRate != null && profile!.payRate! > 0)
        ? profile.payRate
        : null;

    return GestureDetector(
      onTap: _selectionMode
          ? () => _toggleLogSelected(log.id)
          : () {
              HapticFeedback.selectionClick();
              if (log.id < 0 && pid != null) {
                if (canAddAttempt) {
                  _startAttemptForProfile(profile, log);
                } else {
                  _showSnack(
                    'Move within 500 feet of this profile to add an attempt.',
                  );
                }
              } else {
                context.push('/photo/${log.id}');
              }
            },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _exportExcel([log]);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
          border: selected
              ? Border.all(color: _accent, width: 2)
              : Border(
                  left: BorderSide(
                    color: unsuccessful ? const Color(0xFFDC2626) : cat.color,
                    width: unsuccessful ? 4 : 3,
                  ),
                ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Selection radio (selection mode only) ──────────
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 20, right: 12),
                        child: _selectCircle(selected),
                      ),
                    // ── Thumbnail ──────────────────────────────────────
                    Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: (!hasPhoto && canAddAttempt)
                              ? () => _startAttemptForProfile(profile, log)
                              : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: hasPhoto
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Shimmer.fromColors(
                                      baseColor: const Color(0xFFE5E7EB),
                                      highlightColor: const Color(0xFFF9FAFB),
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        color: _canvas,
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      width: 60,
                                      height: 60,
                                      color: _canvas,
                                      child: const Icon(
                                        CupertinoIcons
                                            .photo_fill_on_rectangle_fill,
                                        color: _inkSubtle,
                                        size: 22,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 60,
                                    height: 60,
                                    color: const Color(0xFFE8EEF6),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      CupertinoIcons.placemark_fill,
                                      color: Color(0xFF4A90E2),
                                      size: 26,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (attemptCount == 0 && canAddAttempt)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _startAttemptForProfile(profile, log),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _accentSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.add,
                                    size: 10,
                                    color: _accent,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'Add attempt',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: _accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          Text(
                            attemptLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _inkMuted,
                            ),
                          ),
                          if (canAddAttempt) ...[
                            const SizedBox(height: 4),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  _startAttemptForProfile(profile, log),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CupertinoIcons.add,
                                      size: 10,
                                      color: _accent,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'Add attempt',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: _accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(width: 12),
                    // ── Info ───────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  log.profileName ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (companyName != null &&
                                  companyName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    companyName,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _inkMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Priority (category) badge + distance badge
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (unsuccessful)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                        color: const Color(0xFFDC2626)
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: const Text('No',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFDC2626))),
                                ),
                              PriorityChip(
                                category: log.category,
                                radius: 7,
                                border: true,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                fontSize: 10.5,
                              ),
                              if (payRate != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(
                                    '\$$payRate',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              if (distLabel != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(CupertinoIcons.location_fill,
                                          size: 10,
                                          color: Color(0xFF0284C7)),
                                      const SizedBox(width: 3),
                                      Text(distLabel,
                                          style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0284C7))),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Location row
                          _LocationText(log: log),
                          const SizedBox(height: 2),
                          // Coordinates row — plain reference text below the
                          // address. No leading arrow: the only navigation
                          // affordance is the _LocationText hyperlink above,
                          // so there's a single, unambiguous "open in Maps"
                          // tap target. Indented to align with that link.
                          if (log.latitude.abs() > 0.0001 ||
                              log.longitude.abs() > 0.0001)
                          Padding(
                            padding: const EdgeInsets.only(left: 17),
                            child: Text(
                              _coordsLabel(log),
                              style: const TextStyle(
                                fontSize: 11,
                                color: _inkSubtle,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Timestamp
                          if (log.timestamp != null)
                            Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.clock,
                                  size: 12,
                                  color: _inkSubtle,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _relativeTime(log.timestamp),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _inkSubtle,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 2,
                                  height: 2,
                                  decoration: const BoxDecoration(
                                    color: _inkSubtle,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _fullTime(log.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _inkSubtle,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Note ────────────────────────────────────────────────
              if (log.note != null && log.note!.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          CupertinoIcons.doc_text,
                          size: 12,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.note!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _inkMuted,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    final isFiltered = _hasFilters || _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: _accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.clock,
                size: 38,
                color: _accent,
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 20),
            Text(
              isFiltered ? 'No results' : 'No activity yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.4,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try adjusting your search or filters'
                  : 'Photos you upload will appear here',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _inkSubtle,
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 150.ms),
            if (isFiltered) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  _clearFilters();
                  _rebuild(() {
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Clear all filters',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
            ],
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError(Object error) => Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: _rushRedSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.xmark_circle,
                size: 38,
                color: _rushRed,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connection issue',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().replaceAll('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _inkSubtle,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.invalidate(logProvider(_filters));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

}


class _LocationText extends StatefulWidget {
  const _LocationText({required this.log});
  final LogEntryModel log;
  @override
  State<_LocationText> createState() => _LocationTextState();
}

class _LocationTextState extends State<_LocationText> {
  String? _resolvedAddress;
  // Maps-suitable address (a real street address) — null when we only have a
  // ZIP or raw coordinates, in which case Maps falls back to lat/lng.
  String? _queryAddress;
  bool _fetching = false;
  static const Color _accent = Color(0xFF4A90E2);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  bool get _hasValidCoords =>
      widget.log.latitude.abs() > 0.0001 ||
      widget.log.longitude.abs() > 0.0001;

  void _resolve() async {
    final log = widget.log;
    if (log.address != null && log.address!.trim().isNotEmpty) {
      final addr = log.address!.trim();
      if (log.zipCode != null && log.zipCode!.isNotEmpty && !addr.contains(log.zipCode!)) {
        setState(() {
          _resolvedAddress = '$addr, ${log.zipCode}';
          _queryAddress = '$addr, ${log.zipCode}';
        });
      } else {
        setState(() {
          _resolvedAddress = addr;
          _queryAddress = addr;
        });
      }
      return;
    }
    if (log.zipCode != null && log.zipCode!.isNotEmpty) {
      setState(() => _resolvedAddress = 'ZIP ${log.zipCode}');
      return;
    }
    if (!_hasValidCoords || _fetching) return;
    _fetching = true;
    try {
      final addr = await LocationService.reverseGeocode(log.latitude, log.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() {
          _resolvedAddress = addr;
          _queryAddress = addr;
        });
      }
    } catch (_) {}
    _fetching = false;
  }

  void _openMaps() {
    if (_queryAddress == null && !_hasValidCoords) return;
    HapticFeedback.lightImpact();
    MapsLauncher.openLocation(
      address: _queryAddress,
      lat: widget.log.latitude,
      lng: widget.log.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = _resolvedAddress != null || _hasValidCoords;
    final text = _resolvedAddress ??
        (_hasValidCoords
            ? '${widget.log.latitude.toStringAsFixed(4)}, ${widget.log.longitude.toStringAsFixed(4)}'
            : 'No address set');
    if (!hasLink) {
      return const Row(
        children: [
          Icon(CupertinoIcons.location, size: 13, color: Color(0xFF8B95A5)),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              'No address set',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF8B95A5),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: _openMaps,
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        const Icon(CupertinoIcons.location_fill, size: 13, color: _accent),
        const SizedBox(width: 4),
        Expanded(child: Text(text,
          style: const TextStyle(
            fontSize: 13,
            color: _accent,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: _accent,
          ),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}


