import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../providers/profile_provider.dart';

/// Earnings dashboard — Total vs Available hero, period filters,
/// trend chart, and payouts / timesheets.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  static const _canvas = Color(0xFF0F1219);
  static const _surface = Color(0xFF1C222E);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xFF94A3B8);
  static const _inkSubtle = Color(0xFF6B7A8D);
  static const _border = Color(0xFF2A3340);
  static const _divider = Color(0xFF2A3340);
  static const _accent = Color(0xFF4A90E2);
  static const _accentSoft = Color(0x1F4A90E2);
  static const _success = Color(0xFF059669);

  static const _periods = [
    ['today', 'Today'],
    ['week', 'Week'],
    ['biweekly', 'Bi-Week'],
    ['month', 'Month'],
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
    // Defer until after the first frame — using `ref` during initState throws
    // and can leave the screen stuck on the loading spinner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    ref.invalidate(profilesProvider);
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
          colorScheme:
              Theme.of(ctx).colorScheme.copyWith(primary: _accent),
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

  String get _periodLabel {
    if (_period == 'custom' && _customRange != null) {
      return '${DateFormat('MMM d').format(_customRange!.start)}'
          ' – ${DateFormat('MMM d').format(_customRange!.end)}';
    }
    for (final p in _periods) {
      if (p[0] == _period) return p[1];
    }
    return 'Today';
  }

  @override
  Widget build(BuildContext context) {
    final daily = (_summary?['daily_totals'] as List?) ?? [];
    final payoutDays = (_payouts?['daily'] as List?) ?? [];
    final totalEarnings = (_summary?['total_earnings'] ?? 0) as num;
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const [];
    final localAvailable =
        profiles.fold<int>(0, (sum, p) => sum + (p.payRate ?? 0));
    final availableEarnings =
        (_summary?['available_earnings'] as num?) ?? localAvailable;
    final jobsDone = (_summary?['jobs_completed'] ?? 0) as num;
    final avgPerJob = (_summary?['average_per_job'] ?? 0) as num;
    final highest = _summary?['highest_paying_job'] as Map<String, dynamic>?;
    final lowest = _summary?['lowest_paying_job'] as Map<String, dynamic>?;
    final bottomPad = MediaQuery.of(context).padding.bottom + 88.0;

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: _accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildPeriodSelector()),
              SliverToBoxAdapter(
                child: _buildHeroTotals(
                  totalEarnings: totalEarnings,
                  availableEarnings: availableEarnings,
                  jobsDone: jobsDone,
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _buildMetricsRow(jobsDone, avgPerJob),
                ),
                if (_hasMeaningfulHighlight(highest) ||
                    _hasMeaningfulHighlight(lowest))
                  SliverToBoxAdapter(
                    child: _buildHighlights(highest, lowest),
                  ),
                SliverToBoxAdapter(
                  child: _buildTrendSection(daily),
                ),
                SliverToBoxAdapter(
                  child: _buildPayoutsSection(payoutDays),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasMeaningfulHighlight(Map<String, dynamic>? job) {
    if (job == null) return false;
    return ((job['pay_rate'] ?? 0) as num) > 0;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Earnings',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Completed pay vs open pipeline',
                  style: TextStyle(fontSize: 13, color: _inkSubtle),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _periodLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTotals({
    required num totalEarnings,
    required num availableEarnings,
    required num jobsDone,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total earned',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _money(totalEarnings),
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -1.8,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${jobsDone.toInt()} job${jobsDone == 1 ? '' : 's'} · $_periodLabel',
              style: const TextStyle(fontSize: 13, color: _inkSubtle),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1219),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text(
                    'Available pipeline',
                    style: TextStyle(fontSize: 13, color: _inkMuted),
                  ),
                  const Spacer(),
                  Text(
                    _money(availableEarnings),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _periods.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _periodChip(_periods[i][0], _periods[i][1]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodChip(String key, String label) {
    final sel = _period == key;
    final isCustom = key == 'custom';
    return GestureDetector(
      onTap: () {
        if (isCustom) {
          _pickCustomRange();
        } else {
          setState(() => _period = key);
          _load();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? _accent : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _accent : _border),
        ),
        child: Text(
          isCustom && sel ? _periodLabel : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : _inkMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow(num jobsDone, num avgPerJob) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _metricTile(
              icon: CupertinoIcons.checkmark_seal_fill,
              iconColor: _accent,
              iconBg: _accentSoft,
              label: 'Jobs done',
              value: '${jobsDone.toInt()}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              icon: CupertinoIcons.chart_bar_fill,
              iconColor: const Color(0xFFFBBF24),
              iconBg: const Color(0x26FBBF24),
              label: 'Avg per job',
              value: _money(avgPerJob),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: _inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlights(
    Map<String, dynamic>? highest,
    Map<String, dynamic>? lowest,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Highlights',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _inkMuted,
              ),
            ),
          ),
          Row(
            children: [
              if (_hasMeaningfulHighlight(highest))
                Expanded(
                  child: _highlightCard(
                    label: 'Highest',
                    job: highest!,
                    tone: _success,
                  ),
                ),
              if (_hasMeaningfulHighlight(highest) &&
                  _hasMeaningfulHighlight(lowest))
                const SizedBox(width: 10),
              if (_hasMeaningfulHighlight(lowest))
                Expanded(
                  child: _highlightCard(
                    label: 'Lowest',
                    job: lowest!,
                    tone: const Color(0xFFB45309),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _highlightCard({
    required String label,
    required Map<String, dynamic> job,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: tone,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _money(job['pay_rate']),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            job['profile_name']?.toString() ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          if ((job['address']?.toString().trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 2),
            Text(
              job['address'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: _inkSubtle),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendSection(List<dynamic> daily) {
    final periodTotal =
        daily.fold<num>(0, (s, d) => s + ((d['amount'] ?? 0) as num));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: _section(
        title: 'Earnings trend',
        trailing: daily.isNotEmpty
            ? Text(
                _money(periodTotal),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _success,
                ),
              )
            : null,
        child: daily.isEmpty
            ? _emptyBody(
                icon: CupertinoIcons.chart_bar,
                message: 'No completed jobs in this period.',
              )
            : _trendChart(daily),
      ),
    );
  }

  Widget _trendChart(List<dynamic> daily) {
    final maxAmt = daily.fold<num>(
      0,
      (m, d) => ((d['amount'] ?? 0) as num) > m ? (d['amount'] as num) : m,
    );
    return Column(
      children: [
        for (var i = 0; i < daily.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Builder(builder: (_) {
            final d = daily[i];
            final amt = (d['amount'] ?? 0) as num;
            final frac =
                maxAmt > 0 ? (amt / maxAmt).clamp(0.04, 1.0) : 0.04;
            DateTime? date;
            try {
              date = DateTime.parse(d['date'].toString());
            } catch (_) {}
            final label = date != null
                ? DateFormat('MMM d').format(date)
                : d['date'].toString();
            return Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        children: [
                          Container(color: _divider),
                          FractionallySizedBox(
                            widthFactor: frac.toDouble(),
                            child: Container(color: _accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    _money(amt),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ],
    );
  }

  Widget _buildPayoutsSection(List<dynamic> payoutDays) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: _section(
        title: 'Payouts / timesheets',
        trailing: payoutDays.isNotEmpty
            ? Text(
                '${_money(_payouts?['total_earnings'])}'
                ' · ${_payouts?['total_jobs'] ?? 0}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _success,
                ),
              )
            : null,
        child: payoutDays.isEmpty
            ? _emptyBody(
                icon: CupertinoIcons.doc_text,
                message: 'Close out a job to log a payout.',
              )
            : Column(
                children: [
                  for (var i = 0; i < payoutDays.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 4),
                      const Divider(height: 24, color: _divider),
                    ],
                    _payoutDay(payoutDays[i] as Map<String, dynamic>),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _payoutDay(Map<String, dynamic> d) {
    final entries = (d['entries'] as List?) ?? [];
    DateTime? date;
    try {
      date = DateTime.parse('${d['date']}');
    } catch (_) {}
    final dateLabel = date != null
        ? DateFormat('EEE, MMM d').format(date)
        : '${d['date']}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
            Text(
              _money(d['amount']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${d['jobs']} job${d['jobs'] == 1 ? '' : 's'}'
          ' · running ${_money(d['running_total'])}',
          style: const TextStyle(fontSize: 11.5, color: _inkSubtle),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...entries.map((e) {
            final m = e as Map<String, dynamic>;
            final initial =
                (m['profile_name']?.toString().trim().isNotEmpty ?? false)
                    ? m['profile_name'].toString().trim()[0].toUpperCase()
                    : '?';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['profile_name']?.toString() ?? 'Pin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: _ink,
                          ),
                        ),
                        Text(
                          m['address']?.toString() ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _money(m['pay_rate']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _section({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.2,
                ),
              ),
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

  Widget _emptyBody({required IconData icon, required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 28, color: _inkSubtle),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _inkSubtle,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
