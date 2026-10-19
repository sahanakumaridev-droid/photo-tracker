import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/mileage/mileage_tracker.dart';
import '../../../core/network/api_client.dart';
import '../../providers/profile_provider.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  static const _bg = Color(0xFFF3F6FB);
  static const _ink = Color(0xFF12203A);
  static const _muted = Color(0xFF7A8494);
  static const _blue = Color(0xFF1A56C4);
  static const _periods = [
    ('today', 'Today'),
    ('week', 'Week'),
    ('biweekly', '2 Weeks'),
    ('month', 'Month'),
    ('custom', 'Custom'),
  ];
  static final _usd = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0);

  String _period = 'week';
  DateTimeRange? _customRange;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _payouts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (_summary == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    ref.invalidate(profilesProvider);
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getEarnings(
          period: _period == 'custom' ? 'custom' : _period,
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
        _error = null;
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
    if (key == 'custom') {
      await _pickCustomRange();
      return;
    }
    if (key == _period) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _period = key;
      _customRange = null;
    });
    await _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _customRange = picked;
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

  List<_EarnRow> _rows() {
    final days = (_payouts?['daily'] as List?) ?? [];
    final start = _periodStart;
    final end = _periodEnd;
    final out = <_EarnRow>[];
    for (final d in days) {
      final map = d as Map<String, dynamic>;
      DateTime? date;
      try {
        date = DateTime.parse('${map['date']}');
      } catch (_) {}
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(start) || day.isAfter(end)) continue;
      }
      final entries = (map['entries'] as List?) ?? [];
      if (entries.isEmpty) {
        out.add(_EarnRow(
          name: 'Payout',
          subtitle: date != null ? DateFormat('MMM d, y').format(date) : '',
          date: date,
          amount: (map['amount'] ?? 0) as num,
        ));
      } else {
        for (final e in entries) {
          final m = e as Map<String, dynamic>;
          out.add(_EarnRow(
            name: '${m['profile_name'] ?? 'Attempt'}',
            subtitle: '${m['address'] ?? m['job'] ?? ''}',
            date: date,
            amount: (m['amount'] ?? map['amount'] ?? 0) as num,
          ));
        }
      }
    }
    return out;
  }

  String get _weekChip {
    if (_period == 'custom' && _customRange != null) {
      return '${DateFormat('MMM d').format(_customRange!.start)} – ${DateFormat('MMM d').format(_customRange!.end)}';
    }
    switch (_period) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This Week';
      case 'biweekly':
        return '2 Weeks';
      case 'month':
        return 'This Month';
      default:
        return 'This Week';
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = _chartDays((_summary?['daily_totals'] as List?) ?? []);
    final earned = (_summary?['total_earnings'] ?? 0) as num;
    final available = (_summary?['available_earnings'] ?? 0) as num;
    final jobsDone = ((_summary?['jobs_completed'] ?? 0) as num).toInt();
    final rows = _rows();
    final top = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 88;
    final mileage = MileageTracker.instance;

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: _load,
        color: _blue,
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPad),
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(20, top + 12, 16, 88),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF163EA8), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payouts',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Track your earnings and progress',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _setPeriod(
                      _period == 'week' ? 'month' : 'week',
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.calendar,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _weekChip,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const Icon(CupertinoIcons.chevron_down,
                              size: 14, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _heroMoney(
                            label: 'Total Earnings',
                            value: _loading && _summary == null
                                ? '—'
                                : _money(earned),
                            caption: 'Completed profiles',
                            tint: const Color(0xFFE8F0FF),
                            icon: CupertinoIcons.money_dollar,
                            iconColor: _blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _heroMoney(
                            label: 'Total Available Earnings',
                            value: _loading && _summary == null
                                ? '—'
                                : _money(available),
                            caption: 'Pending and in progress',
                            tint: const Color(0xFFE8F8EE),
                            icon: CupertinoIcons.money_dollar_circle,
                            iconColor: const Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in _periods)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(p.$2),
                                selected: _period == p.$1,
                                onSelected: (_) => _setPeriod(p.$1),
                                selectedColor: _blue,
                                labelStyle: TextStyle(
                                  color: _period == p.$1
                                      ? Colors.white
                                      : _ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                backgroundColor: Colors.white,
                                side: BorderSide.none,
                                shape: const StadiumBorder(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ListenableBuilder(
                      listenable: mileage,
                      builder: (_, __) => Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              color: const Color(0xFFE8F8EE),
                              icon: CupertinoIcons.car_detailed,
                              iconColor: const Color(0xFF16A34A),
                              title: 'Mileage',
                              value: '${mileage.totalMiles.toStringAsFixed(1)} mi',
                              sub:
                                  'Today ${mileage.todayMiles.toStringAsFixed(1)} · Week ${mileage.weekMiles.toStringAsFixed(1)}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statTile(
                              color: const Color(0xFFF1E8FF),
                              icon: CupertinoIcons.checkmark_seal_fill,
                              iconColor: const Color(0xFF7C3AED),
                              title: 'Completed Jobs',
                              value: '$jobsDone',
                              sub: jobsDone == 0
                                  ? 'No completed attempts yet'
                                  : 'This period',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null && _summary == null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(color: Color(0xFFDC2626))),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Text(
                          'Earnings Trend',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _openAll(rows, earned, available),
                          child: const Text('View Details →'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _trend(daily),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Text(
                          'Recent Earnings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => _openAll(rows, earned, available),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _blue,
                            side: const BorderSide(color: Color(0xFFB9D0F5)),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('View All Earnings →'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Close out an attempt and it will land here.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      for (final r in rows.take(4)) _rowTile(r),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAll(List<_EarnRow> rows, num earned, num available) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AllEarningsPage(
          rows: rows,
          earned: earned,
          available: available,
          mileage: MileageTracker.instance.totalMiles,
          money: _money,
        ),
      ),
    );
  }

  Widget _heroMoney({
    required String label,
    required String value,
    required String caption,
    required Color tint,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: _muted,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.8,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(fontSize: 11, color: _muted, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                  fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }

  Widget _trend(List<Map<String, dynamic>> daily) {
    final max = daily.fold<num>(0, (s, d) {
      final a = d['amount'] as num;
      return a > s ? a : s;
    });
    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in daily.take(7))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Text(
                      _money(d['amount']),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _ink),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: max <= 0
                              ? 0.08
                              : ((d['amount'] as num) / max)
                                  .clamp(0.08, 1)
                                  .toDouble(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('E').format(DateTime.parse(d['date'] as String)),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowTile(_EarnRow r) {
    final initial =
        r.name.isNotEmpty ? r.name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE8F0FF),
            child: Text(initial,
                style: const TextStyle(
                    color: _blue, fontWeight: FontWeight.w800)),
          ),
          title: Text(r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [
              if (r.subtitle.trim().isNotEmpty) r.subtitle,
              if (r.date != null) DateFormat('MMM d, y').format(r.date!),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_money(r.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const Icon(CupertinoIcons.chevron_right, size: 16, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarnRow {
  const _EarnRow({
    required this.name,
    required this.subtitle,
    required this.date,
    required this.amount,
  });
  final String name;
  final String subtitle;
  final DateTime? date;
  final num amount;
}

class _AllEarningsPage extends StatefulWidget {
  const _AllEarningsPage({
    required this.rows,
    required this.earned,
    required this.available,
    required this.mileage,
    required this.money,
  });

  final List<_EarnRow> rows;
  final num earned;
  final num available;
  final double mileage;
  final String Function(dynamic) money;

  @override
  State<_AllEarningsPage> createState() => _AllEarningsPageState();
}

class _AllEarningsPageState extends State<_AllEarningsPage> {
  static const _ink = Color(0xFF12203A);
  static const _muted = Color(0xFF7A8494);
  static const _blue = Color(0xFF1A56C4);

  final _search = TextEditingController();
  String _filter = 'all';
  int _shown = 10;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_EarnRow> get _filtered {
    var list = widget.rows;
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) =>
              r.name.toLowerCase().contains(q) ||
              r.subtitle.toLowerCase().contains(q))
          .toList();
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_filter == 'today') {
      list = list
          .where((r) =>
              r.date != null &&
              DateTime(r.date!.year, r.date!.month, r.date!.day) == today)
          .toList();
    } else if (_filter == 'week') {
      final start = today.subtract(Duration(days: today.weekday - 1));
      list = list
          .where((r) => r.date != null && !r.date!.isBefore(start))
          .toList();
    } else if (_filter == 'month') {
      list = list
          .where((r) =>
              r.date != null &&
              r.date!.year == today.year &&
              r.date!.month == today.month)
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final visible = rows.take(_shown).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FB),
        elevation: 0,
        foregroundColor: _ink,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('All Earnings',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('View your complete earnings history',
                style: TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name, job or location',
              prefixIcon: const Icon(CupertinoIcons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in [
                  ('all', 'All'),
                  ('today', 'Today'),
                  ('week', 'Week'),
                  ('month', 'Month'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                      selectedColor: _blue,
                      labelStyle: TextStyle(
                        color: _filter == f.$1 ? Colors.white : _ink,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _mini(
                  const Color(0xFFE8F0FF),
                  'Total Earnings',
                  widget.money(widget.earned),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mini(
                  const Color(0xFFE8F8EE),
                  'Available',
                  widget.money(widget.available),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mini(
                  const Color(0xFFF1E8FF),
                  'Total Mileage',
                  '${widget.mileage.toStringAsFixed(1)} mi',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                  child: Text('Name / Job',
                      style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w700))),
              Text('Date',
                  style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w700)),
              SizedBox(width: 48),
              Text('Amount',
                  style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE8F0FF),
                    child: Text(
                      r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: _blue, fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    r.subtitle.trim().isEmpty ? 'Job' : r.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(widget.money(r.amount),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        r.date == null
                            ? ''
                            : DateFormat('MMM d, y · h:mm a').format(r.date!),
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (rows.length > _shown)
            TextButton(
              onPressed: () => setState(() => _shown += 10),
              child: const Text('Load More'),
            ),
        ],
      ),
    );
  }

  Widget _mini(Color bg, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: _ink)),
        ],
      ),
    );
  }
}
