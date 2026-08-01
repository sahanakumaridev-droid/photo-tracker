import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/attempt_status.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/log_entry_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/log_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/pill_chip.dart';
import '../../widgets/common/stat_card.dart';
import 'resume_attempt_screen.dart';

/// The default screen for the Upload tab. Shows the Total/Pending/
/// Successful/Unsuccessful stat cards (relocated from the Log screen) plus
/// a list of pending attempts, each resumable into a wizard pre-filled with
/// its real, already-saved server data — not a blank form. "+ New Attempt"
/// still opens a blank wizard, identical to the old default `/upload`
/// behavior.
class AttemptsDashboardScreen extends ConsumerWidget {
  const AttemptsDashboardScreen({super.key});

  // ── Design tokens (matches resume_attempt_screen.dart's palette — this
  // screen is reached from the same Upload tab) ──
  static const Color _canvas = Color(0xFFF7F5FF);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);

  static const _emptyFilters = (
    date: null,
    startTime: null,
    endTime: null,
    zipCode: null,
    status: null,
    search: null,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(logProvider(_emptyFilters));

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: logAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _accent),
          ),
          error: (err, _) => _buildError(context, ref, err),
          data: (logs) => _buildBody(context, ref, logs),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: () => _startNewAttempt(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Attempt',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _startNewAttempt(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResumeAttemptScreen()),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<LogEntryModel> logs,
  ) {
    final pending = logs
        .where((l) => normalizeAttemptStatus(l.attemptStatus) ==
            kAttemptStatusPending)
        .toList()
      ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: _buildStatRow(logs)),
        SliverToBoxAdapter(child: _buildSectionLabel(pending.length)),
        if (pending.isEmpty)
          SliverToBoxAdapter(child: _buildEmptyPending(context))
        else
          SliverList.builder(
            itemCount: pending.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _PendingAttemptCard(log: pending[i]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
        color: _surface,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attempts',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.8,
                height: 1.1,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Resume an in-progress attempt or start a new one',
              style: TextStyle(
                fontSize: 13,
                color: _inkSubtle,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  // ── Stat row — Total/Pending/Successful/Unsuccessful over every attempt
  // app-wide, same counting pattern the Log screen's stat row used. ──
  Widget _buildStatRow(List<LogEntryModel> logs) {
    final total = logs.length;
    int countOf(String status) => logs
        .where((l) => normalizeAttemptStatus(l.attemptStatus) == status)
        .length;
    final cards = [
      StatCard(
        label: 'Total',
        value: '$total',
        icon: CupertinoIcons.square_grid_2x2_fill,
        iconColor: _accent,
        iconBg: _accentSoft,
      ),
      StatCard(
        label: kAttemptStatuses[0].label,
        value: '${countOf(kAttemptStatusPending)}',
        icon: kAttemptStatuses[0].icon,
        iconColor: kAttemptStatuses[0].color,
        iconBg: kAttemptStatuses[0].softColor,
      ),
      StatCard(
        label: kAttemptStatuses[1].label,
        value: '${countOf(kAttemptStatusSuccessful)}',
        icon: kAttemptStatuses[1].icon,
        iconColor: kAttemptStatuses[1].color,
        iconBg: kAttemptStatuses[1].softColor,
      ),
      StatCard(
        label: kAttemptStatuses[2].label,
        value: '${countOf(kAttemptStatusUnsuccessful)}',
        icon: kAttemptStatuses[2].icon,
        iconColor: kAttemptStatuses[2].color,
        iconBg: kAttemptStatuses[2].softColor,
      ),
    ];
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 10),
            Expanded(child: cards[3]),
          ]),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Row(
          children: [
            const Text(
              'Pending Attempts',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyPending(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.checkmark_seal,
                    size: 30, color: _accent),
              ),
              const SizedBox(height: 16),
              const Text(
                'No pending attempts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Everything is up to date. Start a new attempt to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _inkMuted, height: 1.4),
              ),
            ],
          ),
        ),
      );

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
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                err.toString().replaceAll('Exception: ', ''),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _inkSubtle),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => ref.invalidate(logProvider(_emptyFilters)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}

/// One pending-attempt row: profile name, company, priority chip, relative
/// time, and a Resume button that fetches the profile's full attempts to
/// find the matching real [Attempt] before opening the wizard.
class _PendingAttemptCard extends ConsumerStatefulWidget {
  const _PendingAttemptCard({required this.log});

  final LogEntryModel log;

  @override
  ConsumerState<_PendingAttemptCard> createState() =>
      _PendingAttemptCardState();
}

class _PendingAttemptCardState extends ConsumerState<_PendingAttemptCard> {
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _accent = Color(0xFF7C3AED);

  bool _loading = false;

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
      Attempt? match;
      for (final a in attempts) {
        if (a.id == log.id) {
          match = a;
          break;
        }
      }
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    final companyName = profile?.companyName ??
        companyOrDefault(profile?.company).name;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.profileName ?? profile?.name ?? 'Unknown profile',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  companyName,
                  style: const TextStyle(fontSize: 12.5, color: _inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PriorityChip(
                      category: log.category,
                      radius: 7,
                      border: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      fontSize: 10.5,
                    ),
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.clock,
                        size: 11, color: _inkSubtle),
                    const SizedBox(width: 3),
                    Text(
                      _relativeTime(log.timestamp),
                      style: const TextStyle(fontSize: 11.5, color: _inkSubtle),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _loading ? null : _resume,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accent.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Resume',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
