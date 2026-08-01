import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/stat_card.dart';

/// F8 / F9 — Earnings dashboard (Uber-driver style) + Payouts / Timesheets.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  static const _periods = [
    ['today', 'Today'],
    ['week', 'This Week'],
    ['biweekly', 'Bi-Weekly'],
    ['month', 'Monthly'],
    ['custom', 'Custom'],
  ];

  String _period = 'today';
  DateTimeRange? _customRange;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _payouts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getEarnings(
          period: _period,
          startDate: _period == 'custom' && _customRange != null
              ? DateFormat('yyyy-MM-dd').format(_customRange!.start)
              : null,
          endDate: _period == 'custom' && _customRange != null
              ? DateFormat('yyyy-MM-dd').format(_customRange!.end)
              : null,
        ),
        api.getPayouts(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0];
        _payouts = results[1];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _customRange = picked;
    });
    _load();
  }

  String _money(dynamic n) =>
      '\$${((n ?? 0) as num).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final daily = (_summary?['daily_totals'] as List?) ?? [];
    final payoutDays = (_payouts?['daily'] as List?) ?? [];
    final totalEarnings = (_summary?['total_earnings'] ?? 0) as num;
    final availableEarnings = (_summary?['available_earnings'] ?? 0) as num;
    final jobsDone = (_summary?['jobs_completed'] ?? 0) as num;
    final avgPerJob = (_summary?['average_per_job'] ?? 0) as num;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: CustomScrollView(
          slivers: [
            // ── Gradient hero header ──
            SliverAppBar(
              expandedHeight: 190,
              pinned: true,
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              title: const Text(
                'Earnings',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _heroBackground(
                    totalEarnings, availableEarnings, jobsDone),
              ),
            ),

            // ── Body ──
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period selector — sits on the purple→grey seam
                  _periodSelector(),

                  const SizedBox(height: 16),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: LoadingSkeletonCard()),
                              SizedBox(width: 12),
                              Expanded(child: LoadingSkeletonCard()),
                            ],
                          ),
                          SizedBox(height: 12),
                          LoadingSkeleton(height: 160),
                        ],
                      ),
                    )
                  else ...[
                    // Stat cards
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              label: 'Jobs Done',
                              value: '$jobsDone',
                              icon: CupertinoIcons.checkmark_circle,
                              iconColor: AppTheme.primary,
                              iconBg: AppTheme.primarySoft,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              label: 'Avg Per Job',
                              value: _money(avgPerJob),
                              icon: CupertinoIcons.chart_bar,
                              iconColor: AppTheme.warning,
                              iconBg: const Color(0xFFFEF3C7),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Highest / Lowest highlights
                    if (_summary?['highest_paying_job'] != null ||
                        _summary?['lowest_paying_job'] != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_summary?['highest_paying_job'] != null)
                              _jobHighlight(
                                title: 'Highest',
                                icon: CupertinoIcons.arrow_up_right,
                                color: AppTheme.success,
                                job: _summary!['highest_paying_job']
                                    as Map<String, dynamic>,
                              ),
                            if (_summary?['highest_paying_job'] != null &&
                                _summary?['lowest_paying_job'] != null)
                              const SizedBox(width: 12),
                            if (_summary?['lowest_paying_job'] != null)
                              _jobHighlight(
                                title: 'Lowest',
                                icon: CupertinoIcons.arrow_down_right,
                                color: AppTheme.warning,
                                job: _summary!['lowest_paying_job']
                                    as Map<String, dynamic>,
                              ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Earnings Trend
                    _sectionCard(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      title: 'Earnings Trend',
                      trailing: daily.isNotEmpty
                          ? _badge(
                              _money(daily.fold<num>(
                                  0,
                                  (s, d) =>
                                      s + ((d['amount'] ?? 0) as num))),
                              AppTheme.success)
                          : null,
                      child: daily.isEmpty
                          ? _emptyState(
                              icon: CupertinoIcons.chart_bar_alt_fill,
                              message:
                                  'No completed jobs in this period yet.')
                          : _trendChart(daily),
                    ),

                    const SizedBox(height: 12),

                    // Payouts / Timesheets
                    _sectionCard(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      title: 'Payouts / Timesheets',
                      trailing: payoutDays.isNotEmpty
                          ? Text(
                              '${_money(_payouts?['total_earnings'])} · ${_payouts?['total_jobs'] ?? 0} jobs',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success))
                          : null,
                      child: payoutDays.isEmpty
                          ? _emptyState(
                              icon: CupertinoIcons.doc_text_fill,
                              message:
                                  'No closed jobs yet. Close out a pin to log a payout.')
                          : Column(
                              children: payoutDays
                                  .map((d) =>
                                      _payoutDay(d as Map<String, dynamic>))
                                  .toList(),
                            ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero gradient background shown behind the collapsed app bar ──
  Widget _heroBackground(
      num totalEarnings, num availableEarnings, num jobsDone) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _heroStat('Total Earnings', totalEarnings),
                  ),
                  Container(
                    width: 1,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  Expanded(
                    child: _heroStat(
                        'Total Available Earnings', availableEarnings),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${jobsDone.toInt()} job${jobsDone == 1 ? '' : 's'} completed',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String label, num amount) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2)),
          const SizedBox(height: 4),
          Text(
            _money(amount),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1),
          ),
        ],
      );

  // ── Period pills — bridging the purple header to the grey body ──
  Widget _periodSelector() {
    return Container(
      color: AppTheme.primaryDark,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F4F7),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _periods.map((p) {
              final sel = _period == p[0];
              final isCustom = p[0] == 'custom';
              final label = isCustom && sel && _customRange != null
                  ? '${DateFormat('MMM d').format(_customRange!.start)} '
                      '– ${DateFormat('MMM d').format(_customRange!.end)}'
                  : p[1];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    if (isCustom) {
                      _pickCustomRange();
                    } else {
                      setState(() => _period = p[0]);
                      _load();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: sel
                            ? AppTheme.primary
                            : const Color(0xFFE5E7EB),
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color:
                                    AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCustom) ...[
                          Icon(CupertinoIcons.calendar,
                              size: 12,
                              color: sel
                                  ? Colors.white
                                  : AppTheme.lightTextSecondary),
                          const SizedBox(width: 5),
                        ] else if (sel) ...[
                          const Icon(CupertinoIcons.checkmark,
                              size: 13, color: Colors.white),
                          const SizedBox(width: 5),
                        ],
                        Text(label,
                            style: TextStyle(
                                color: sel
                                    ? Colors.white
                                    : AppTheme.lightText,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Horizontal bar chart for daily trend ──
  Widget _trendChart(List<dynamic> daily) {
    final maxAmt = daily.fold<num>(
        0,
        (m, d) =>
            ((d['amount'] ?? 0) as num) > m
                ? (d['amount'] as num)
                : m);
    return Column(
      children: daily.map((d) {
        final amt = (d['amount'] ?? 0) as num;
        final frac =
            maxAmt > 0 ? (amt / maxAmt).clamp(0.03, 1.0) : 0.03;
        DateTime? date;
        try {
          date = DateTime.parse(d['date'].toString());
        } catch (_) {}
        final label = date != null
            ? DateFormat('MMM d').format(date)
            : d['date'].toString();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: frac.toDouble(),
                      child: Container(
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withValues(alpha: 0.75),
                              AppTheme.primary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 42,
                child: Text(
                  _money(amt),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.success),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Payout day group ──
  Widget _payoutDay(Map<String, dynamic> d) {
    final entries = (d['entries'] as List?) ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day header row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${d['date']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
              const SizedBox(width: 8),
              Text(
                '${d['jobs']} job${d['jobs'] == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
              const Spacer(),
              Text(
                _money(d['amount']),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.success,
                    fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              'Running total: ${_money(d['running_total'])}',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
          // Entry rows
          ...entries.map((e) {
            final m = e as Map<String, dynamic>;
            final c =
                _catColor[(m['category'] ?? 'standard').toString()] ??
                    AppTheme.primary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Colored avatar circle
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['profile_name']?.toString() ?? 'Pin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5)),
                        const SizedBox(height: 1),
                        Text(m['address']?.toString() ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _money(m['pay_rate']),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (entries.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        ],
      ),
    );
  }

  // ── Highest / Lowest job card ──
  Widget _jobHighlight({
    required String title,
    required IconData icon,
    required Color color,
    required Map<String, dynamic> job,
  }) {
    final c = _catColor[(job['category'] ?? 'standard').toString()] ??
        AppTheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 7),
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
            const SizedBox(height: 10),
            Text(_money(job['pay_rate']),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(job['profile_name']?.toString() ?? 'Pin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
              ],
            ),
            if (job['address'] != null) ...[
              const SizedBox(height: 2),
              Text(job['address'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ],
        ),
      ),
    );
  }

  // ── Reusable section card ──
  Widget _sectionCard({
    required EdgeInsets margin,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Empty-state placeholder ──
  Widget _emptyState({required IconData icon, required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  // ── Small green pill badge ──
  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  static const _catColor = {
    'asap': Color(0xFFEF4444),
    'special': Color(0xFFF59E0B),
    'next_day': Color(0xFFEAB308),
    'standard': Color(0xFF10B981),
  };
}
