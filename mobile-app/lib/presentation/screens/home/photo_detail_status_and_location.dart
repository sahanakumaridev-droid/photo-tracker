part of 'photo_detail_screen.dart';

extension _PhotoDetailStatusExt on _PhotoDetailScreenState {
  ProfileModel? _profileFor(PhotoModel photo) {
    final id = photo.profileId ??
        ((photo.profiles != null && photo.profiles!.isNotEmpty)
            ? photo.profiles!.first.id
            : null);
    if (id != null) {
      for (final p in ref.watch(profilesProvider).valueOrNull ?? const []) {
        if (p.id == id) return p;
      }
    }
    if (photo.profiles != null && photo.profiles!.isNotEmpty) {
      return photo.profiles!.first;
    }
    return null;
  }

  Widget _buildStatusCard(PhotoModel photo) {
    final profile = _profileFor(photo);
    final current = normalizeProfileStatus(profile?.status ?? photo.status);
    final currentIndex = _statusSteps.indexOf(current);
    final color = _statusColor(current);
    final attempts = profile?.attemptsCount ?? 0;
    final cap = profile?.attemptCap ?? 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_statusIcon(current), size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JOB STATUS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _inkSubtle,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _statusLabel(current),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              // Step counter badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$attempts / $cap',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Stepper
          _buildJobStepper(currentIndex, photo),
          const SizedBox(height: 14),
          // Hint row
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: _inkSubtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'The first unsuccessful attempt sets In Progress. '
                    'After $cap unsuccessful attempts, or one successful attempt, '
                    'the job is Completed. Archive only after payment is confirmed.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _inkSubtle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Horizontal stepper track
  Widget _buildJobStepper(int currentIndex, PhotoModel photo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _statusSteps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                // top: 19 centres the 2px line on the 40px circle (40/2 − 1)
                padding: const EdgeInsets.only(top: 19),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  height: 2,
                  decoration: BoxDecoration(
                    color: i <= currentIndex
                        ? _statusColor(_statusSteps[i - 1])
                        : const Color(0xFFE8ECF0),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          _buildStepNode(i, currentIndex, photo),
        ],
      ],
    );
  }

  // Individual step node (circle + label)
  Widget _buildStepNode(int index, int currentIndex, PhotoModel photo) {
    final step = _statusSteps[index];
    final isCompleted = index < currentIndex;
    final isActive = index == currentIndex;
    final isFuture = index > currentIndex;
    final stepColor = _statusColor(step);

    final profile = _profileFor(photo);
    final canArchive = step == kProfileArchived &&
        profile != null &&
        profile.canArchive;
    return GestureDetector(
      onTap: canArchive ? () => _archiveFromDetail(profile) : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? stepColor
                  : isCompleted
                      ? stepColor.withValues(alpha: 0.12)
                      : const Color(0xFFEEF1F5),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? stepColor
                    : isCompleted
                        ? stepColor.withValues(alpha: 0.5)
                        : const Color(0xFFE3E7EE),
                width: isActive ? 0 : 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: stepColor.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : _statusIcon(step),
              size: 18,
              color: isActive
                  ? Colors.white
                  : isCompleted
                      ? stepColor
                      : const Color(0xFFB0B8C4),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: 58,
            child: Text(
              _statusLabel(step),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? stepColor
                    : isFuture
                        ? const Color(0xFFB0B8C4)
                        : _inkMuted,
                height: 1.25,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Status summary (shown when job is completed / archived) ──────────────
  Widget _buildStatusSummaryCard(PhotoModel photo) {
    final steps = [
      _SummaryStep(
        status: 'open',
        label: 'Opened',
        icon: Icons.radio_button_unchecked,
        timestamp: photo.createdAt ?? photo.timestamp,
        color: _airportBlue,
      ),
      const _SummaryStep(
        status: 'in_progress',
        label: 'In Progress',
        icon: Icons.sync_rounded,
        timestamp: null,
        color: Color(0xFFF59E0B),
      ),
      _SummaryStep(
        status: 'completed',
        label: 'Completed',
        icon: Icons.check_circle_rounded,
        timestamp: photo.completedAt,
        color: _standardGreen,
      ),
      if (photo.status == 'archived')
        const _SummaryStep(
          status: 'archived',
          label: 'Archived',
          icon: Icons.inventory_2_rounded,
          timestamp: null,
          color: _inkSubtle,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _standardGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.format_list_bulleted_rounded,
                    size: 18, color: _standardGreen),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STATUS SUMMARY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _inkSubtle,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Full job lifecycle',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Timeline rows
          for (int i = 0; i < steps.length; i++) ...[
            _buildSummaryRow(steps[i], isLast: i == steps.length - 1),
          ],
          // Closing line item — a distinct entry added when the job closes,
          // summarising how it was closed (payout, closing note, time).
          if (photo.status == 'completed' || photo.status == 'archived')
            _buildClosingLineItem(photo),
        ],
      ),
    );
  }

  // Distinct closing summary appended on close — relates the lifecycle to the
  // concrete outcome of the job (what was paid, any closing note).
  Widget _buildClosingLineItem(PhotoModel photo) {
    final isArchived = photo.status == 'archived';
    final details = <String>[];
    if (photo.payRate != null) details.add('Payout \$${photo.payRate}');
    if (photo.note != null && photo.note!.trim().isNotEmpty) {
      details.add(photo.note!.trim());
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isArchived ? Icons.inventory_2_rounded : Icons.task_alt_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArchived ? 'Job Closed & Archived' : 'Job Closed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTs(photo.completedAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _inkMuted,
                    height: 1.3,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join('  •  '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _inkMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(_SummaryStep step, {required bool isLast}) {
    final formattedTs = step.timestamp != null
        ? _formatTs(step.timestamp)
        : '—';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: icon + vertical connector
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: step.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, size: 17, color: step.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _separator,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Right: label + timestamp
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: step.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formattedTs,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Generic info card ─────────────────────────────────────────────────────
  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    Widget? trailing,
  }) =>
      Container(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _inkSubtle,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  // ── Location card ─────────────────────────────────────────────────────────
  Widget _buildLocationCard(PhotoModel photo) {
    final hasAddress = photo.address != null && photo.address!.isNotEmpty;
    final hasZip = photo.zipCode != null && photo.zipCode!.isNotEmpty;
    final coordsText = '${photo.latitude.toStringAsFixed(6)}, '
        '${photo.longitude.toStringAsFixed(6)}';

    // Priority: stored address → live-resolved address → ZIP → coords
    String locationDisplay;
    if (hasAddress) {
      final addr = photo.address!;
      if (hasZip && !addr.contains(photo.zipCode!)) {
        locationDisplay = '$addr, ${photo.zipCode}';
      } else {
        locationDisplay = addr;
      }
    } else if (_resolvedAddress != null) {
      // Live reverse-geocoded from lat/lng — full street address
      locationDisplay = _resolvedAddress!;
    } else if (_resolvingAddress) {
      locationDisplay = 'Fetching address…';
    } else if (hasZip) {
      locationDisplay = 'ZIP ${photo.zipCode}';
    } else {
      locationDisplay = coordsText;
    }

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOCATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _inkSubtle,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Human-readable address — tap to open in Maps
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _openInMaps(photo);
                      },
                      child: Text(
                        locationDisplay,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                          decoration: TextDecoration.underline,
                          decorationColor: _accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Always show raw coordinates below
                    Text(
                      coordsText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _inkMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: _separator, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.map_rounded,
                  label: 'Open in Maps',
                  color: _accent,
                  onTap: () => _openInMaps(photo),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy Coords',
                  color: const Color(0xFF0284C7),
                  onTap: () => _copyCoords(photo.latitude, photo.longitude),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );

  // ── Profile tags ──────────────────────────────────────────────────────────
  Widget _buildProfileTags(PhotoModel photo) => Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LINKED PROFILES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _inkSubtle,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photo.profiles!
                  .where((p) => p.id != photo.profileId)
                  .map((p) {
                final color = _svcColor(p.serviceType);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  // ── Delete button ─────────────────────────────────────────────────────────
  Widget _buildDeleteButton(PhotoModel photo) => GestureDetector(
        onTap: () => _confirmDelete(photo),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _rushRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _rushRed.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: _rushRed),
              SizedBox(width: 8),
              Text(
                'Delete Photo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _rushRed,
                ),
              ),
            ],
          ),
        ),
      );

  void _confirmDelete(PhotoModel photo) {
    HapticFeedback.mediumImpact();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Photo',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This photo will be permanently deleted. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(deletePhotoProvider(photo.id).future);
                if (mounted) {
                  _goBack(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Photo deleted'),
                      backgroundColor: _rushRed,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } on Exception catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: _rushRed,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _rushRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Back button ───────────────────────────────────────────────────────────
  void _goBack(BuildContext context) {
    HapticFeedback.lightImpact();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  Widget _backButton(BuildContext context, {bool dark = true}) =>
      GestureDetector(
        onTap: () => _goBack(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: dark
                ? Colors.black.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.chevron_left_rounded,
            size: 16,
            color: dark ? _ink : Colors.white,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Photo Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

