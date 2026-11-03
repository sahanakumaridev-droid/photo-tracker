part of 'photo_detail_screen.dart';

extension _PhotoDetailScaffoldExt on _PhotoDetailScreenState {
  Widget _buildDetailScaffold(PhotoModel photo, List<PhotoModel> allPhotos) {
    // Priority reflects the per-photo category (serviceType is the legacy
    // profile field and is no longer the source of truth for priority).
    final groups = _attemptGroups(photo, allPhotos);
    var attemptIdx = 0;
    var photoIdx = 0;
    for (var i = 0; i < groups.length; i++) {
      final j = groups[i].indexWhere((p) => p.id == photo.id);
      if (j >= 0) {
        attemptIdx = i;
        photoIdx = j;
        break;
      }
    }
    final attemptPhotos = groups[attemptIdx];
    // Open on the newest attempt. Later swipes update [_shownAttempt].
    if (_attemptPageCtrl == null) _shownAttempt = 0;
    final shown = _shownAttempt.clamp(0, groups.length - 1);
    final attemptNumber = groups.length - shown;
    // Page 0 is an off-screen "new attempt" slot to the left of the newest.
    final attemptPage = shown + 1;
    if (_viewingPhotoId == null && groups.isNotEmpty) {
      final latestId = groups.first.first.id;
      if (photo.id != latestId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rebuild(() => _viewingPhotoId = latestId);
        });
      }
    }
    _ensureSwipeControllers(
      attemptPage: attemptPage,
      photoIdx: photoIdx,
      attemptIdx: attemptIdx,
    );
    if (!_attemptPagerReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuild(() => _attemptPagerReady = true);
      });
    }

    final topPad = MediaQuery.paddingOf(context).top;
    final photoH = (_imageExpanded ? 420.0 : 300.0) + topPad + 8;

    Widget photoDots() {
      if (attemptPhotos.isEmpty) return const SizedBox.shrink();
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < attemptPhotos.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: i == photoIdx ? 8 : 7,
              height: i == photoIdx ? 8 : 7,
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == photoIdx
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: i == photoIdx ? 0 : 0.8,
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          SizedBox(
            height: photoH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: PageView.builder(
                    controller: _photoPageCtrl,
                    physics: attemptPhotos.length <= 1
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    itemCount: attemptPhotos.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      _rebuild(() => _viewingPhotoId = attemptPhotos[i].id);
                    },
                    itemBuilder: (_, i) {
                      final p = attemptPhotos[i];
                      return GestureDetector(
                        onDoubleTap: () {
                          HapticFeedback.lightImpact();
                          _rebuild(() => _imageExpanded = !_imageExpanded);
                        },
                        child: CachedNetworkImage(
                          imageUrl: _fullUrl(p.imageUrl),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white38,
                              size: 48,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.only(top: topPad),
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: Row(
                        children: [
                          _backButton(context, dark: false),
                          const Spacer(),
                          GestureDetector(
                            onLongPress: () => _exportJob(photo),
                            child: IconButton(
                              icon: const Icon(Icons.ios_share_rounded,
                                  color: Colors.white),
                              tooltip:
                                  'Email this attempt — long-press to share the photo',
                              onPressed: () =>
                                  _exportJob(photo, email: true),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Colors.white),
                            tooltip: 'Edit photo',
                            onPressed: () => _showEditSheet(photo),
                          ),
                          IconButton(
                            icon: Icon(
                              _imageExpanded
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _rebuild(
                                  () => _imageExpanded = !_imageExpanded);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: topPad + 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${photo.id}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                WatermarkCaption(
                  takenAtIso: photo.takenAt ?? photo.timestamp,
                  address: photo.address ?? '',
                  zipCode: photo.zipCode,
                  fileNumber: photo.fileNumber,
                  profileName: photo.profileName,
                  latitude: photo.latitude,
                  longitude: photo.longitude,
                  below: photoDots(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              groups.length <= 1
                  ? 'Attempt 1 of 1  ·  swipe this card right for a new attempt'
                  : shown == 0
                      ? 'Attempt $attemptNumber of ${groups.length}  ·  swipe left for older'
                      : shown == groups.length - 1
                          ? 'Attempt $attemptNumber of ${groups.length}  ·  first attempt'
                          : 'Attempt $attemptNumber of ${groups.length}  ·  swipe left for older',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _inkMuted,
              ),
            ),
          ),
          Expanded(
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                _AttemptSwipe:
                    GestureRecognizerFactoryWithHandlers<_AttemptSwipe>(
                  _AttemptSwipe.new,
                  (_AttemptSwipe instance) {
                    instance.onUpdate = (d) {
                      final ctrl = _attemptPageCtrl;
                      if (ctrl == null || !ctrl.hasClients) return;
                      final pos = ctrl.position;
                      final next = (pos.pixels - d.delta.dx)
                          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
                      pos.jumpTo(next);
                    };
                    instance.onEnd = (d) {
                      final ctrl = _attemptPageCtrl;
                      if (ctrl == null || !ctrl.hasClients) return;
                      final page = ctrl.page ?? 0;
                      final velocity = d.primaryVelocity ?? 0;
                      var target = page.round();
                      if (velocity.abs() > 280) {
                        target = velocity > 0 ? page.floor() : page.ceil();
                      }
                      target = target.clamp(0, groups.length);
                      unawaited(ctrl.animateToPage(
                        target,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                      ));
                    };
                  },
                ),
              },
              child: PageView.builder(
                controller: _attemptPageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groups.length + 1,
                onPageChanged: (i) {
                  if (!_attemptPagerReady) return;
                  if (i == 0) {
                    unawaited(_openNewAttempt(photo));
                    return;
                  }
                  HapticFeedback.selectionClick();
                  _rebuild(() {
                    _shownAttempt = i - 1;
                    _viewingPhotoId = groups[i - 1].first.id;
                  });
                },
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return const _NewAttemptPeek();
                  }
                  final shown =
                      (i - 1) == attemptIdx ? photo : groups[i - 1].first;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildAttemptDetails(
                      shown,
                      categoryOf(shown.category).color,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptDetails(PhotoModel photo, Color svcColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeader(photo, svcColor),
        const SizedBox(height: 14),
        _buildDetailsGroup(
          title: 'Job',
          children: [
            _detailRow(
              'File Number',
              (photo.fileNumber != null &&
                      photo.fileNumber!.trim().isNotEmpty)
                  ? photo.fileNumber!
                  : '—',
            ),
            _detailRow(
              'Job Status',
              (photo.status ?? 'open').replaceAll('_', ' '),
            ),
            if (photo.payRate != null && photo.payRate! > 0)
              _detailRow('Payout', '\$${photo.payRate}'),
          ],
        ),
        const SizedBox(height: 12),
        if (photo.status == 'completed' || photo.status == 'archived') ...[
          _buildStatusSummaryCard(photo),
          const SizedBox(height: 12),
        ],
        _buildDetailsGroup(
          title: 'Attempt',
          children: [
            _detailRow(
              'Attempt Status',
              attemptStatusByValue(photo.attemptStatus)?.label ??
                  photo.attemptStatus,
            ),
            _detailRow(
              'Captured',
              _formatTs(photo.timestamp),
              trailing: _withinTsWindow(photo)
                  ? TextButton(
                      onPressed: () => _editTimestamp(photo),
                      child: const Text('Edit'),
                    )
                  : null,
            ),
            _detailRow(
              'Delivery Style',
              (photo.completionType != null &&
                      photo.completionType!.trim().isNotEmpty)
                  ? photo.completionType!
                  : '—',
            ),
            _detailRow(
              'Served To',
              (photo.servedTo != null && photo.servedTo!.trim().isNotEmpty)
                  ? photo.servedTo!
                  : '—',
            ),
            _detailRow(
              'Relation To',
              (photo.relationTo != null &&
                      photo.relationTo!.trim().isNotEmpty)
                  ? photo.relationTo!
                  : '—',
            ),
            _detailRow(
              'Note',
              (photo.note != null && photo.note!.trim().isNotEmpty)
                  ? photo.note!
                  : '—',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildLocationCard(photo),
        const SizedBox(height: 12),
        _buildStatusCard(photo),
        if (photo.profiles != null &&
            photo.profiles!
                .where((p) => p.id != photo.profileId)
                .isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildProfileTags(photo),
        ],
        const SizedBox(height: 24),
        _buildDeleteButton(photo),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────
  Widget _buildProfileHeader(PhotoModel photo, Color svcColor) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: svcColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (photo.profileName ?? 'U')[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: svcColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.profileName ?? 'Unknown Profile',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        categoryOf(photo.category).icon,
                        size: 13,
                        color: svcColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        categoryOf(photo.category).label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: svcColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildDetailsGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _ink,
                height: 1.3,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ── F10: job lifecycle status card ────────────────────────────────────────
}
