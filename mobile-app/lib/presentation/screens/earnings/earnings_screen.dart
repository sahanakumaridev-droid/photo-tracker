import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/ai_spark_button.dart';
import '../../widgets/common/loading_skeleton.dart';

/// Wallet-style earnings: one number, a daily chart, and a payout ledger.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  static const _bg = AppTheme.darkBg;
  static const _surface = AppTheme.darkSurface;
  static const _elevated = AppTheme.darkElevated;
  static const _ink = AppTheme.darkText;
  static const _muted = AppTheme.darkTextSecondary;
  static const _subtle = AppTheme.darkTextTertiary;
  static const _hair = AppTheme.darkBorder;
  static const _accent = AppTheme.primary;
  static const _success = Color(0xFF34D399);

  static const _easeOut = Cubic(0.23, 1, 0.32, 1);
  static const _periods = [
    ('today', 'Today'),
    ('week', 'Week'),
    ('biweekly', '2 Wks'),
    ('month', 'Month'),
  ];

  static final _usd = NumberFormat.simpleCurrency(
    name: 'USD',
    decimalDigits: 0,
  );
  static const _tabular = [FontFeature.tabularFigures()];

  String _period = 'week';
  DateTimeRange? _customRange;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _payouts;
  bool _loading = true;
  String? _error;
  int? _selectedBar;
  final Set<String> _openDays = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final first = _summary == null;
    if (first) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

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
      final payouts = results[1];
      final days = (payouts['daily'] as List?) ?? [];
      setState(() {
        _summary = results[0];
        _payouts = payouts;
        _loading = false;
        _error = null;
        _selectedBar = null;
        if (_openDays.isEmpty && days.isNotEmpty) {
          _openDays.add('${days.first['date']}');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load earnings. Pull to retry.';
      });
    }
  }

  Future<void> _setPeriod(String key) async {
    if (key == _period) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _period = key;
      _customRange = null;
      _selectedBar = null;
    });
    await _load();
  }

  Future<void> _pickCustomRange() async {
    unawaited(HapticFeedback.selectionClick());
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _accent,
            onPrimary: Colors.white,
            surface: _surface,
            onSurface: _ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _customRange = picked;
      _selectedBar = null;
    });
    await _load();
  }

  String _money(dynamic n) => _usd.format((n ?? 0) as num);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _periodStart {
    final today = _today;
    switch (_period) {
      case 'today':
        return today;
      case 'week':
        return today.subtract(Duration(days: today.weekday - 1));
      case 'biweekly':
        return today.subtract(const Duration(days: 13));
      case 'month':
        return DateTime(today.year, today.month, 1);
      case 'custom':
        if (_customRange != null) {
          final s = _customRange!.start;
          return DateTime(s.year, s.month, s.day);
        }
        return today;
      default:
        return today.subtract(Duration(days: today.weekday - 1));
    }
  }

  DateTime get _periodEnd {
    final today = _today;
    switch (_period) {
      case 'week':
        return _periodStart.add(const Duration(days: 6));
      case 'month':
        return DateTime(today.year, today.month + 1, 0);
      case 'custom':
        if (_customRange != null) {
          final e = _customRange!.end;
          return DateTime(e.year, e.month, e.day);
        }
        return today;
      default:
        return today;
    }
  }

  List<Map<String, dynamic>> _chartDays(List<dynamic> raw) {
    final byDate = <String, num>{};
    for (final d in raw) {
      final key = '${d['date']}'.split('T').first;
      if (key.length >= 10) {
        byDate[key.substring(0, 10)] = (d['amount'] ?? 0) as num;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (var d = _periodStart;
        !d.isAfter(_periodEnd);
        d = d.add(const Duration(days: 1))) {
      final key = DateFormat('yyyy-MM-dd').format(d);
      out.add({'date': key, 'amount': byDate[key] ?? 0});
    }
    return out;
  }

  List<dynamic> _payoutsInPeriod(List<dynamic> days) {
    final start = _periodStart;
    final end = _periodEnd;
    return days.where((d) {
      final date = _parseDate(d['date']);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
  }

  String get _chartTitle {
    switch (_period) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This week';
      case 'biweekly':
        return 'Last 2 weeks';
      case 'month':
        return 'This month';
      case 'custom':
        return 'Selected range';
      default:
        return 'Daily';
    }
  }

  String get _periodLabel {
    if (_period == 'custom' && _customRange != null) {
      return '${DateFormat('MMM d').format(_customRange!.start)}'
          ' – ${DateFormat('MMM d').format(_customRange!.end)}';
    }
    switch (_period) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This week';
      case 'biweekly':
        return 'Last 2 weeks';
      case 'month':
        return 'This month';
      default:
        return 'This week';
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = _chartDays((_summary?['daily_totals'] as List?) ?? []);
    final payoutDays =
        _payoutsInPeriod((_payouts?['daily'] as List?) ?? []);
    final totalEarnings = (_summary?['total_earnings'] ?? 0) as num;
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const [];
    final photos = ref.watch(photosProvider).valueOrNull ?? const [];
    final openJobs = _openJobs(profiles, photos);
    final jobsDone = (_summary?['jobs_completed'] ?? 0) as num;
    final avgPerJob = (_summary?['average_per_job'] ?? 0) as num;
    final highest = _summary?['highest_paying_job'] as Map<String, dynamic>?;
    final bottomPad = MediaQuery.of(context).padding.bottom + 88;
    final showSkeleton = _loading && _summary == null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: _accent,
          backgroundColor: _surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _periodControl()),
              if (_error != null && _summary == null)
                SliverToBoxAdapter(child: _errorState())
              else if (showSkeleton)
                SliverToBoxAdapter(child: _skeleton())
              else ...[
                SliverToBoxAdapter(
                  child: _hero(total: totalEarnings, jobsDone: jobsDone),
                ),
                if (openJobs.isNotEmpty)
                  SliverToBoxAdapter(child: _openJobsCard(openJobs)),
                SliverToBoxAdapter(
                  child: _trendCard(daily),
                ),
                SliverToBoxAdapter(
                  child: _statsStrip(
                    jobsDone: jobsDone,
                    avgPerJob: avgPerJob,
                    highest: highest,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _activity(payoutDays),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Earnings',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -1.2,
                height: 1.1,
              ),
            ),
          ),
          const AiSparkButton(),
        ],
      ),
    );
  }

  Widget _periodControl() {
    final selectedIndex = _periods.indexWhere((p) => p.$1 == _period);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    if (selectedIndex >= 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 1 / _periods.length,
                          heightFactor: 1,
                          child: AnimatedSlide(
                            offset: Offset(selectedIndex.toDouble(), 0),
                            duration: const Duration(milliseconds: 200),
                            curve: _easeOut,
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        for (var i = 0; i < _periods.length; i++)
                          Expanded(
                            child: _Pressable(
                              onTap: () => _setPeriod(_periods[i].$1),
                              child: SizedBox.expand(
                                child: Center(
                                  child: Text(
                                    _periods[i].$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selectedIndex == i
                                          ? _ink
                                          : _muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Pressable(
            onTap: _pickCustomRange,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _period == 'custom' ? _accent : _elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                CupertinoIcons.calendar,
                size: 18,
                color: _period == 'custom' ? Colors.white : _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero({
    required num total,
    required num jobsDone,
  }) {
    final jobs = jobsDone.toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _periodLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(total),
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -2.4,
                height: 1,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            jobs == 0
                ? 'No completed attempts yet'
                : '$jobs attempt${jobs == 1 ? '' : 's'} completed',
            style: const TextStyle(fontSize: 15, color: _subtle, height: 1.2),
          ),
        ],
      ),
    );
  }

  /// Profiles that still have a pay rate and are not fully closed out.
  List<({String name, int pay})> _openJobs(
    List<ProfileModel> profiles,
    List<PhotoModel> photos,
  ) {
    final apiJobs = _summary?['open_jobs'] as List?;
    if (apiJobs != null && apiJobs.isNotEmpty) {
      return [
        for (final j in apiJobs)
          (
            name: '${j['name'] ?? 'Job'}',
            pay: ((j['pay_rate'] ?? 0) as num).toInt(),
          ),
      ].where((j) => j.pay > 0).toList();
    }

    final byProfile = <int, List<PhotoModel>>{};
    for (final ph in photos) {
      final id = ph.profileId;
      if (id == null) continue;
      byProfile.putIfAbsent(id, () => []).add(ph);
    }

    final out = <({String name, int pay})>[];
    for (final p in profiles) {
      final rate = p.payRate;
      if (rate == null || rate <= 0) continue;
      final shots = byProfile[p.id] ?? const <PhotoModel>[];
      if (shots.isNotEmpty &&
          shots.every((ph) {
            final s = (ph.status ?? '').toLowerCase();
            return s == 'completed' || s == 'archived';
          })) {
        continue;
      }
      out.add((name: p.name, pay: rate));
    }
    return out;
  }

  Widget _openJobsCard(List<({String name, int pay})> jobs) {
    final total = jobs.fold<int>(0, (s, j) => s + j.pay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: _group(
        title: 'Unfinished jobs',
        trailing: Text(
          _money(total),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ink,
            fontFeatures: _tabular,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 12),
              child: Text(
                'Pay assigned to jobs you have not closed out. '
                'This is not a payout — it moves into the total above when you complete them.',
                style: TextStyle(fontSize: 13, height: 1.35, color: _muted),
              ),
            ),
            const Divider(height: 1, color: _hair),
            for (var i = 0; i < jobs.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _hair),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        jobs[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _money(jobs[i].pay),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        fontFeatures: _tabular,
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

  Widget _trendCard(List<dynamic> daily) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: _group(
        title: _chartTitle,
        trailing: Text(
                DateFormat('MMM d').format(_periodStart) ==
                        DateFormat('MMM d').format(_periodEnd)
                    ? DateFormat('MMM d').format(_periodStart)
                    : '${DateFormat('MMM d').format(_periodStart)}'
                        ' – ${DateFormat('MMM d').format(_periodEnd)}',
                style: const TextStyle(fontSize: 13, color: _subtle),
              ),
        child: daily.isEmpty
            ? _empty(
                icon: CupertinoIcons.chart_bar,
                message: 'Complete an attempt to see a daily trend.',
              )
            : _chart(daily),
      ),
    );
  }

  Widget _chart(List<dynamic> daily) {
    final maxAmt = daily.fold<num>(
      0,
      (m, d) => ((d['amount'] ?? 0) as num) > m ? (d['amount'] as num) : m,
    );
    final selected = () {
      if (_selectedBar != null &&
          _selectedBar! >= 0 &&
          _selectedBar! < daily.length) {
        return _selectedBar!;
      }
      final todayKey = DateFormat('yyyy-MM-dd').format(_today);
      final todayIdx =
          daily.indexWhere((d) => '${d['date']}' == todayKey);
      if (todayIdx >= 0) return todayIdx;
      for (var i = daily.length - 1; i >= 0; i--) {
        if (((daily[i]['amount'] ?? 0) as num) > 0) return i;
      }
      return daily.isEmpty ? 0 : daily.length - 1;
    }();

    return SizedBox(
      height: 176,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < daily.length; i++)
            Expanded(
              child: _DayBar(
                date: _parseDate(daily[i]['date']),
                amount: (daily[i]['amount'] ?? 0) as num,
                fraction: maxAmt > 0
                    ? ((daily[i]['amount'] ?? 0) as num) / maxAmt
                    : 0,
                selected: i == selected,
                dense: daily.length > 10,
                money: _money,
                period: _period,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() => _selectedBar = i);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsStrip({
    required num jobsDone,
    required num avgPerJob,
    required Map<String, dynamic>? highest,
  }) {
    final bits = <String>[
      '${jobsDone.toInt()} closed',
      '${_money(avgPerJob)} avg',
    ];
    if (highest != null && ((highest['pay_rate'] ?? 0) as num) > 0) {
      final name = (highest['profile_name']?.toString().trim().isNotEmpty ??
              false)
          ? highest['profile_name'].toString()
          : 'attempt';
      bits.add('Best ${_money(highest['pay_rate'])} · $name');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Text(
        bits.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: _subtle, height: 1.3),
      ),
    );
  }

  Widget _activity(List<dynamic> payoutDays) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: _group(
        title: 'Payouts',
        trailing: payoutDays.isEmpty
            ? null
            : Text(
                '${_money(payoutDays.fold<num>(0, (s, d) => s + ((d['amount'] ?? 0) as num)))}'
                ' · ${payoutDays.fold<int>(0, (s, d) => s + ((d['jobs'] ?? 0) as num).toInt())}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _success,
                  fontFeatures: _tabular,
                ),
              ),
        child: payoutDays.isEmpty
            ? _empty(
                icon: CupertinoIcons.doc_text,
                message: 'Close out an attempt and it will land here.',
              )
            : Column(
                children: [
                  for (var i = 0; i < payoutDays.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 0, color: _hair),
                    _dayGroup(payoutDays[i] as Map<String, dynamic>),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _dayGroup(Map<String, dynamic> d) {
    final key = '${d['date']}';
    final open = _openDays.contains(key);
    final entries = (d['entries'] as List?) ?? [];
    final date = _parseDate(d['date']);
    final dateLabel = date != null
        ? DateFormat('EEE, MMM d').format(date)
        : key;

    return Column(
      children: [
        _Pressable(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            setState(() {
              if (open) {
                _openDays.remove(key);
              } else {
                _openDays.add(key);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${d['jobs']} attempt${d['jobs'] == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, color: _subtle),
                      ),
                    ],
                  ),
                ),
                Text(
                  _money(d['amount']),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _success,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: _easeOut,
                  child: const Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: _subtle,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open && entries.isNotEmpty)
          ...entries.map((e) => _entryRow(e as Map<String, dynamic>)),
      ],
    );
  }

  Widget _entryRow(Map<String, dynamic> m) {
    final name = m['profile_name']?.toString().trim();
    final initial = (name != null && name.isNotEmpty)
        ? name[0].toUpperCase()
        : '?';
    final address = m['address']?.toString().trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1F4A90E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Attempt' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _subtle),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(m['pay_rate']),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: _ink,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }

  Widget _group({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _empty({required IconData icon, required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 22, color: _subtle),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _subtle, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 28,
            color: _subtle,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Something went wrong',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 16),
          _Pressable(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: _elevated,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Try again',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingSkeleton(
            width: 72,
            height: 14,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          SizedBox(height: 12),
          LoadingSkeleton(
            width: 180,
            height: 48,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          SizedBox(height: 10),
          LoadingSkeleton(
            width: 140,
            height: 14,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          SizedBox(height: 24),
          LoadingSkeleton(
            width: double.infinity,
            height: 176,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ],
      ),
    );
  }

  DateTime? _parseDate(dynamic raw) {
    try {
      return DateTime.parse('$raw');
    } catch (_) {
      return null;
    }
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.date,
    required this.amount,
    required this.fraction,
    required this.selected,
    required this.dense,
    required this.money,
    required this.period,
    required this.onTap,
  });

  final DateTime? date;
  final num amount;
  final num fraction;
  final bool selected;
  final bool dense;
  final String Function(dynamic) money;
  final String period;
  final VoidCallback onTap;

  static const _easeOut = Cubic(0.23, 1, 0.32, 1);

  String get _label {
    if (date == null) return '';
    if (period == 'today') return DateFormat('EEE').format(date!);
    if (period == 'month' || dense) return DateFormat('d').format(date!);
    return DateFormat('E').format(date!).substring(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final frac = fraction <= 0 ? 0.03 : fraction.clamp(0.03, 1.0).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            SizedBox(
              height: 18,
              child: selected
                  ? Text(
                      money(amount),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _EarningsScreenState._ink,
                        fontFeatures: _EarningsScreenState._tabular,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: frac,
                  widthFactor: dense ? 0.7 : 0.85,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: _easeOut,
                    decoration: BoxDecoration(
                      color: selected
                          ? _EarningsScreenState._accent
                          : const Color(0x664A90E2),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? _EarningsScreenState._ink
                    : _EarningsScreenState._subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
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
        child: widget.child,
      ),
    );
  }
}
