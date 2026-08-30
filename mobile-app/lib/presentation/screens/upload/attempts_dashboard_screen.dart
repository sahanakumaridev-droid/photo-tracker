import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/attempt_snapshot_store.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/category.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/log_entry_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/log_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../settings/ai_assistant_sheet.dart';
import '../../widgets/common/create_profile_dialog.dart';
import '../../widgets/common/pill_chip.dart';
import 'attempt_draft_controller.dart';
import 'attempt_limits.dart';
import 'resume_attempt_screen.dart';

/// Locally-cached attempts (Quick Save / Save & Exit / poor-network
/// auto-save) — not yet, or not fully, uploaded to the server.
final localSnapshotsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => AttemptSnapshotStore.readAll());

/// One photo row per Attempt (multi-photo attempts would otherwise appear
/// repeatedly). Prefer [LogEntryModel.attemptId]; fall back to photo id.
List<LogEntryModel> _uniqueByAttempt(Iterable<LogEntryModel> logs) {
  final seen = <int>{};
  final out = <LogEntryModel>[];
  for (final log in logs) {
    final key = log.attemptId ?? log.id;
    if (seen.add(key)) out.add(log);
  }
  return out;
}

/// Resolve a log photo row to its real [Attempt] (log.id is a photo id).
Attempt? _matchAttempt(List<Attempt> attempts, LogEntryModel log) {
  if (log.attemptId != null) {
    for (final a in attempts) {
      if (a.id == log.attemptId) return a;
    }
  }
  for (final a in attempts) {
    if (a.id == log.id) return a;
    for (final p in a.photos) {
      if (p.id == log.id) return a;
    }
  }
  return null;
}

/// Upload-tab home: profiles grouped by priority. Attempts are added
/// from a profile after it exists.
class AttemptsDashboardScreen extends ConsumerStatefulWidget {
  const AttemptsDashboardScreen({super.key});

  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _border = Color(0xFFE3E7EE);

  static const _emptyFilters = (
    date: null,
    startTime: null,
    endTime: null,
    zipCode: null,
    status: null,
    search: null,
  );

  @override
  ConsumerState<AttemptsDashboardScreen> createState() =>
      _AttemptsDashboardScreenState();
}

class _AttemptsDashboardScreenState
    extends ConsumerState<AttemptsDashboardScreen> {
  _StatFilter _filter = _StatFilter.total;

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    return Scaffold(
      backgroundColor: AttemptsDashboardScreen._canvas,
      body: SafeArea(
        bottom: false,
        child: profilesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
                color: AttemptsDashboardScreen._accent),
          ),
          error: (err, _) => _buildError(context, ref, err),
          data: (profiles) => _buildBody(context, ref, profiles),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<ProfileModel> profiles,
  ) {
    final photos = ref.watch(photosProvider).valueOrNull ?? const <PhotoModel>[];
    final rows = [
      for (final p in profiles)
        _ProfileDashRow(
          profile: p,
          photos: photos
              .where((ph) =>
                  ph.profileId == p.id ||
                  (ph.profiles?.any((x) => x.id == p.id) ?? false))
              .toList()
            ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? '')),
        ),
    ];

    final pending = rows.where((r) => r.bucket == _StatFilter.pending).toList();
    final done = rows.where((r) => r.bucket == _StatFilter.done).toList();
    final failed = rows.where((r) => r.bucket == _StatFilter.failed).toList();

    final filtered = switch (_filter) {
      _StatFilter.total => rows,
      _StatFilter.pending => pending,
      _StatFilter.done => done,
      _StatFilter.failed => failed,
    };

    final grouped = <String, List<_ProfileDashRow>>{};
    for (final r in filtered) {
      grouped.putIfAbsent(r.category.label, () => []).add(r);
    }
    final sections = [
      for (final c in kPhotoCategories)
        if (grouped[c.label]?.isNotEmpty == true) (c, grouped[c.label]!),
    ];
    for (final e in grouped.entries) {
      if (sections.any((s) => s.$1.label == e.key)) continue;
      sections.add((categoryOf(e.key.toLowerCase()), e.value));
    }

    final bottomPad = MediaQuery.of(context).padding.bottom + 88.0;

    return Column(
      children: [
        _buildHeader(context),
        _buildStatStrip(
          total: rows.length,
          pending: pending.length,
          done: done.length,
          failed: failed.length,
        ),
        Expanded(
          child: RefreshIndicator(
            color: AttemptsDashboardScreen._accent,
            onRefresh: () async {
              ref.invalidate(profilesProvider);
              ref.invalidate(photosProvider);
              await Future.wait([
                ref.read(profilesProvider.future),
                ref.read(photosProvider.future),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyList(_filter),
                  )
                else
                  for (final section in sections) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Icon(section.$1.icon,
                                size: 16, color: section.$1.color),
                            const SizedBox(width: 8),
                            Text(
                              section.$1.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: section.$1.color,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${section.$2.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AttemptsDashboardScreen._inkSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      sliver: SliverList.separated(
                        itemCount: section.$2.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) => _ProfileDashCard(
                          row: section.$2[i],
                          onOpen: () =>
                              context.push('/profile/${section.$2[i].profile.id}'),
                        ),
                      ),
                    ),
                  ],
                SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AttemptsDashboardScreen._surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profiles',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AttemptsDashboardScreen._ink,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Create a profile, then add up to 5 attempts',
                  style: TextStyle(
                    fontSize: 13,
                    color: AttemptsDashboardScreen._inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: AttemptsDashboardScreen._accent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _openNewProfile(context),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'New Profile',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNewProfile(BuildContext context) async {
    HapticFeedback.lightImpact();
    final created = await showCreateProfileDialog(context);
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profile "${created.name}" created'),
        action: SnackBarAction(
          label: 'Add attempt',
          onPressed: () => context.push(
            '/new-attempt?profileId=${created.id}',
            extra: created,
          ),
        ),
      ),
    );
  }

  Widget _buildStatStrip({
    required int total,
    required int pending,
    required int done,
    required int failed,
  }) {
    final items = [
      (
        _StatFilter.total,
        'Total',
        '$total',
        AttemptsDashboardScreen._accent,
        AttemptsDashboardScreen._accentSoft,
      ),
      (
        _StatFilter.pending,
        'Pending',
        '$pending',
        kAttemptStatuses[0].color,
        kAttemptStatuses[0].softColor,
      ),
      (
        _StatFilter.done,
        'Completed',
        '$done',
        kAttemptStatuses[1].color,
        kAttemptStatuses[1].softColor,
      ),
      (
        _StatFilter.failed,
        'Failed',
        '$failed',
        kAttemptStatuses[2].color,
        kAttemptStatuses[2].softColor,
      ),
    ];

    return Container(
      color: AttemptsDashboardScreen._surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AttemptsDashboardScreen._canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AttemptsDashboardScreen._border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _StatCell(
                  label: items[i].$2,
                  value: items[i].$3,
                  color: items[i].$4,
                  soft: items[i].$5,
                  selected: _filter == items[i].$1,
                  showDivider: i > 0 &&
                      _filter != items[i].$1 &&
                      _filter != items[i - 1].$1,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _filter = items[i].$1);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyList(_StatFilter filter) {
    final (icon, color, soft, title, subtitle) = switch (filter) {
      _StatFilter.total => (
          CupertinoIcons.person_2,
          AttemptsDashboardScreen._accent,
          AttemptsDashboardScreen._accentSoft,
          'No profiles yet',
          'Tap New Profile to create one. Attempts are added after.',
        ),
      _StatFilter.pending => (
          kAttemptStatuses[0].icon,
          kAttemptStatuses[0].color,
          kAttemptStatuses[0].softColor,
          'No pending profiles',
          'Profiles waiting on an attempt show up here.',
        ),
      _StatFilter.done => (
          kAttemptStatuses[1].icon,
          kAttemptStatuses[1].color,
          kAttemptStatuses[1].softColor,
          'No completed profiles',
          'Profiles with a successful attempt show up here.',
        ),
      _StatFilter.failed => (
          kAttemptStatuses[2].icon,
          kAttemptStatuses[2].color,
          kAttemptStatuses[2].softColor,
          'No failed profiles',
          'Profiles whose latest attempt failed show up here.',
        ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AttemptsDashboardScreen._ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AttemptsDashboardScreen._inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object err) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.xmark_circle,
                  size: 38, color: Color(0xFFDC2626)),
              const SizedBox(height: 16),
              const Text(
                'Connection issue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AttemptsDashboardScreen._ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                err.toString().replaceAll('Exception: ', ''),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AttemptsDashboardScreen._inkSubtle),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => ref.invalidate(profilesProvider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AttemptsDashboardScreen._accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}

enum _StatFilter { total, pending, done, failed }

class _ProfileDashRow {
  _ProfileDashRow({required this.profile, required this.photos});

  final ProfileModel profile;
  final List<PhotoModel> photos;

  int get attemptCount => jobAttemptCount(
        photos: photos,
        profileAttemptsCount: profile.attemptsCount,
      );

  PhotoModel? get latest => photos.isEmpty ? null : photos.first;

  PhotoCategory get category => categoryOf(profile.serviceType);

  _StatFilter get bucket {
    if (attemptCount == 0) return _StatFilter.pending;
    final st = normalizeAttemptStatus(latest?.attemptStatus);
    if (st == kAttemptStatusSuccessful) return _StatFilter.done;
    if (st == kAttemptStatusUnsuccessful) return _StatFilter.failed;
    return _StatFilter.pending;
  }
}

class _ProfileDashCard extends StatelessWidget {
  const _ProfileDashCard({
    required this.row,
    required this.onOpen,
  });

  final _ProfileDashRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = row.profile;
    final cat = row.category;
    final n = row.attemptCount;
    final company = (p.companyName?.trim().isNotEmpty == true)
        ? p.companyName!
        : companyOrDefault(p.company).name;

    return Material(
      color: AttemptsDashboardScreen._surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AttemptsDashboardScreen._border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cat.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AttemptsDashboardScreen._ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          company,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AttemptsDashboardScreen._inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PillChip(
                    label: cat.label,
                    icon: cat.icon,
                    color: cat.color,
                    background: cat.softColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                n == 0
                    ? 'No attempts yet · 0 of ${AttemptDraftController.kMaxAttemptsPerJob}'
                    : '$n of ${AttemptDraftController.kMaxAttemptsPerJob} attempts',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AttemptsDashboardScreen._inkSubtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatefulWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
    required this.soft,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final Color soft;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  State<_StatCell> createState() => _StatCellState();
}

class _StatCellState extends State<_StatCell> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.23, 1, 0.32, 1),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected ? widget.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.showDivider
                ? const Border(
                    left: BorderSide(color: AttemptsDashboardScreen._border),
                  )
                : null,
          ),
          child: Column(
            children: [
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: widget.color,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.selected
                      ? AttemptsDashboardScreen._ink
                      : AttemptsDashboardScreen._inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttemptListCard extends ConsumerStatefulWidget {
  const _AttemptListCard({
    required this.log,
    required this.statusValue,
  });

  final LogEntryModel log;
  final String statusValue;

  @override
  ConsumerState<_AttemptListCard> createState() => _AttemptListCardState();
}

class _AttemptListCardState extends ConsumerState<_AttemptListCard> {
  bool _loading = false;

  AttemptStatusOption get _status =>
      attemptStatusByValue(widget.statusValue) ?? kAttemptStatuses.first;

  String _relativeTime(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return '';
    }
  }

  Future<void> _resume() async {
    final log = widget.log;
    final profileId = log.profileId;
    if (profileId == null) {
      _showSnack('This entry has no linked profile.', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final attempts =
          await ref.read(profileAttemptsProvider(profileId).future);
      final match = _matchAttempt(attempts, log);
      if (!mounted) return;
      if (match == null) {
        _showSnack('Could not find that attempt — it may have changed.',
            isError: true);
        return;
      }
      HapticFeedback.selectionClick();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResumeAttemptScreen(resumeAttempt: match),
        ),
      );
      ref.invalidate(localSnapshotsProvider);
      ref.invalidate(logProvider(AttemptsDashboardScreen._emptyFilters));
    } catch (_) {
      if (mounted) {
        _showSnack('Could not load this attempt. Try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final profilesAsync = ref.watch(profilesProvider);
    ProfileModel? profile;
    for (final p in profilesAsync.valueOrNull ?? const <ProfileModel>[]) {
      if (p.id == log.profileId) {
        profile = p;
        break;
      }
    }
    final companyName =
        profile?.companyName ?? companyOrDefault(profile?.company).name;
    final status = _status;
    final subtitle = (log.fileNumber?.trim().isNotEmpty ?? false)
        ? 'File #${log.fileNumber} · $companyName'
        : (log.address?.trim().isNotEmpty ?? false)
            ? '${log.address} · $companyName'
            : companyName;
    final isUnsuccessful =
        widget.statusValue == kAttemptStatusUnsuccessful;

    return Material(
      color: AttemptsDashboardScreen._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _loading ? null : _resume,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AttemptsDashboardScreen._border),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  color: status.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.profileName ?? profile?.name ?? 'Unknown profile',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AttemptsDashboardScreen._ink,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AttemptsDashboardScreen._inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        PriorityChip(
                          category: log.category,
                          radius: 6,
                          border: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          fontSize: 10,
                        ),
                        const Spacer(),
                        Text(
                          _relativeTime(log.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AttemptsDashboardScreen._inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (_loading)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AttemptsDashboardScreen._accent,
                      ),
                    ),
                  ),
                )
              else
                Tooltip(
                  message: isUnsuccessful ? 'Open' : 'Resume',
                  child: IconButton(
                    onPressed: _resume,
                    icon: Icon(
                      isUnsuccessful
                          ? CupertinoIcons.chevron_right
                          : CupertinoIcons.play_arrow_solid,
                      size: 18,
                      color: AttemptsDashboardScreen._accent,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AttemptsDashboardScreen._accentSoft,
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
