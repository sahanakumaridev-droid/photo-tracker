import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/attempt_snapshot_store.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/log_entry_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/log_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/pill_chip.dart';
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

/// Upload-tab home: compact summary + Pending / Unsuccessful tabs.
/// "New Attempt" lives in the header (no FAB overlapping the bottom nav).
class AttemptsDashboardScreen extends ConsumerStatefulWidget {
  const AttemptsDashboardScreen({super.key});

  static const Color _canvas = Color(0xFF0F1219);
  static const Color _surface = Color(0xFF1C222E);
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _inkMuted = Color(0xFF94A3B8);
  static const Color _inkSubtle = Color(0xFF6B7A8D);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _border = Color(0xFF2A3340);
  static const Color _divider = Color(0xFF2A3340);

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
    extends ConsumerState<AttemptsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logAsync =
        ref.watch(logProvider(AttemptsDashboardScreen._emptyFilters));
    final snapshots = ref.watch(localSnapshotsProvider).valueOrNull ??
        const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: AttemptsDashboardScreen._canvas,
      body: SafeArea(
        bottom: false,
        child: logAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
                color: AttemptsDashboardScreen._accent),
          ),
          error: (err, _) => _buildError(context, ref, err),
          data: (logs) => _buildBody(context, ref, logs, snapshots),
        ),
      ),
    );
  }

  Future<void> _startNewAttempt(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResumeAttemptScreen()),
    );
    ref.invalidate(localSnapshotsProvider);
    ref.invalidate(logProvider(AttemptsDashboardScreen._emptyFilters));
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<LogEntryModel> logs,
    List<Map<String, dynamic>> snapshots,
  ) {
    final pending = _uniqueByAttempt(
      logs.where((l) =>
          normalizeAttemptStatus(l.attemptStatus) == kAttemptStatusPending),
    )..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));

    final unsuccessful = _uniqueByAttempt(
      logs.where((l) =>
          normalizeAttemptStatus(l.attemptStatus) ==
          kAttemptStatusUnsuccessful),
    )..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));

    final showingPending = _tabController.index == 0;
    final activeList = showingPending ? pending : unsuccessful;
    // Clearance for the elevated Upload tab in the shell bottom nav.
    final bottomPad = MediaQuery.of(context).padding.bottom + 88.0;

    return Column(
      children: [
        _buildHeader(context, ref),
        _buildStatStrip(logs),
        _buildTabs(
          pendingCount: pending.length,
          unsuccessfulCount: unsuccessful.length,
        ),
        Expanded(
          child: RefreshIndicator(
            color: AttemptsDashboardScreen._accent,
            onRefresh: () async {
              ref.invalidate(localSnapshotsProvider);
              ref.invalidate(
                  logProvider(AttemptsDashboardScreen._emptyFilters));
              await ref.read(
                  logProvider(AttemptsDashboardScreen._emptyFilters).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (showingPending && snapshots.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _buildDraftsBanner(snapshots.length),
                  ),
                  SliverList.builder(
                    itemCount: snapshots.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _QuickSavedCard(snapshot: snapshots[i]),
                    ),
                  ),
                  if (activeList.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          'On server',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AttemptsDashboardScreen._inkSubtle,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                ],
                if (activeList.isEmpty &&
                    !(showingPending && snapshots.isNotEmpty))
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyList(isPending: showingPending),
                  )
                else if (activeList.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    sliver: SliverList.separated(
                      itemCount: activeList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _AttemptListCard(
                        log: activeList[i],
                        statusValue: showingPending
                            ? kAttemptStatusPending
                            : kAttemptStatusUnsuccessful,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
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
                  'Attempts',
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
                  'Track, resume, or start a new job',
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
              onTap: () => _startNewAttempt(context, ref),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'New',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatStrip(List<LogEntryModel> logs) {
    final unique = _uniqueByAttempt(logs);
    int countOf(String status) => unique
        .where((l) => normalizeAttemptStatus(l.attemptStatus) == status)
        .length;

    final items = [
      (
        'Total',
        '${unique.length}',
        AttemptsDashboardScreen._accent,
        AttemptsDashboardScreen._accentSoft,
      ),
      (
        'Pending',
        '${countOf(kAttemptStatusPending)}',
        kAttemptStatuses[0].color,
        kAttemptStatuses[0].softColor,
      ),
      (
        'Done',
        '${countOf(kAttemptStatusSuccessful)}',
        kAttemptStatuses[1].color,
        kAttemptStatuses[1].softColor,
      ),
      (
        'Failed',
        '${countOf(kAttemptStatusUnsuccessful)}',
        kAttemptStatuses[2].color,
        kAttemptStatuses[2].softColor,
      ),
    ];

    return Container(
      color: AttemptsDashboardScreen._surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: AttemptsDashboardScreen._canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AttemptsDashboardScreen._border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 28,
                  color: AttemptsDashboardScreen._border,
                ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: items[i].$3,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[i].$1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AttemptsDashboardScreen._inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabs({
    required int pendingCount,
    required int unsuccessfulCount,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: AttemptsDashboardScreen._surface,
        border: Border(
          bottom: BorderSide(color: AttemptsDashboardScreen._border),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: AttemptsDashboardScreen._accent,
        indicatorWeight: 2.5,
        labelColor: AttemptsDashboardScreen._ink,
        unselectedLabelColor: AttemptsDashboardScreen._inkMuted,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(
            child: _TabLabel(
              title: 'Pending',
              count: pendingCount,
              active: _tabController.index == 0,
            ),
          ),
          Tab(
            child: _TabLabel(
              title: 'Unsuccessful',
              count: unsuccessfulCount,
              active: _tabController.index == 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftsBanner(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Drafts on this device · $count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyList({required bool isPending}) {
    final opt = isPending ? kAttemptStatuses[0] : kAttemptStatuses[2];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: opt.softColor,
                shape: BoxShape.circle,
              ),
              child: Icon(opt.icon, size: 26, color: opt.color),
            ),
            const SizedBox(height: 16),
            Text(
              isPending ? 'No pending attempts' : 'No unsuccessful attempts',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AttemptsDashboardScreen._ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPending
                  ? 'Tap New to start logging a service attempt.'
                  : 'Failed attempts will appear in this tab.',
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
                onPressed: () => ref.invalidate(
                    logProvider(AttemptsDashboardScreen._emptyFilters)),
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

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.title,
    required this.count,
    required this.active,
  });

  final String title;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: active
                ? AttemptsDashboardScreen._accentSoft
                : AttemptsDashboardScreen._divider,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active
                  ? AttemptsDashboardScreen._accent
                  : AttemptsDashboardScreen._inkMuted,
            ),
          ),
        ),
      ],
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
                        _MiniChip(
                          label: status.label,
                          fg: status.color,
                          bg: status.softColor,
                        ),
                        const SizedBox(width: 6),
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

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _QuickSavedCard extends ConsumerStatefulWidget {
  const _QuickSavedCard({required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  ConsumerState<_QuickSavedCard> createState() => _QuickSavedCardState();
}

class _QuickSavedCardState extends ConsumerState<_QuickSavedCard> {
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberSoft = Color(0x26F59E0B);
  static const Color _amberBorder = Color(0x66F59E0B);

  bool _opening = false;

  String? get _subtitle {
    final snapshot = widget.snapshot;
    final fileNumber = (snapshot['fileNumber'] as String?)?.trim();
    if (fileNumber != null && fileNumber.isNotEmpty) return 'File #$fileNumber';
    final address = (snapshot['address'] as String?)?.trim();
    if (address != null && address.isNotEmpty) return address;
    final style = (snapshot['completionType'] as String?)?.trim();
    if (style != null && style.isNotEmpty) return style;
    return null;
  }

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
    setState(() => _opening = true);
    HapticFeedback.selectionClick();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ResumeAttemptScreen(localSnapshot: widget.snapshot),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
      ref.invalidate(localSnapshotsProvider);
      ref.invalidate(logProvider(AttemptsDashboardScreen._emptyFilters));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final isExisting = snapshot['existingAttemptId'] != null;
    final photoCount = (snapshot['photoPaths'] as List?)?.length ?? 0;

    return Material(
      color: _amberSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _opening ? null : _resume,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _amberBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sd_storage_outlined,
                    size: 16, color: _amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExisting ? 'Unsynced edit' : 'Local draft',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _amber,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (snapshot['profileName'] as String?) ??
                          'Unknown profile',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AttemptsDashboardScreen._ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (_subtitle != null) _subtitle!,
                        if (photoCount > 0)
                          '$photoCount photo${photoCount > 1 ? 's' : ''}',
                        _relativeTime(snapshot['snapshotAt'] as String?),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AttemptsDashboardScreen._inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_opening)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _amber,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: _resume,
                  icon: const Icon(CupertinoIcons.play_arrow_solid,
                      size: 18, color: _amber),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1C222E),
                    minimumSize: const Size(36, 36),
                    fixedSize: const Size(36, 36),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
