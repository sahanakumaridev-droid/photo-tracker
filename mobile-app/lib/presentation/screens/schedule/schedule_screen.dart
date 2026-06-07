import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';

/// F4 — Service-level scheduling queues.
/// Gradient summary hero + tabbed queues with premium job cards.
/// Virtualized lists keep it smooth with large datasets.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _Queue {
  const _Queue(this.key, this.label, this.color, this.icon);
  final String key;
  final String label;
  final Color color;
  final IconData icon;
}

const _queues = [
  _Queue('asap', 'ASAP', Color(0xFFEF4444), Icons.bolt_rounded),
  _Queue('special', 'Special', Color(0xFFF59E0B), Icons.star_rounded),
  _Queue('next_day', 'Next Day', Color(0xFFEAB308), Icons.fast_forward_rounded),
  _Queue('standard', 'Standard', Color(0xFF10B981), Icons.check_circle_rounded),
];

class _ScheduleScreenState extends ConsumerState<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: _queues.length, vsync: this);
  Map<String, dynamic> _queueData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(apiServiceProvider).getSchedule();
      if (!mounted) return;
      setState(() {
        _queueData = (data['queues'] as Map?)?.cast<String, dynamic>() ?? {};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String key) => (_queueData[key] as List?)?.length ?? 0;
  int get _total => _queues.fold(0, (s, q) => s + _count(q.key));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Schedule'),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _hero(),
                _tabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: _queues.map(_queueList).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Gradient summary hero ─────────────────────────────────────────────────
  Widget _hero() => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1B4D), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Active jobs',
                style: TextStyle(color: Color(0xFFCBB6FF), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$_total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1.05)),
            const SizedBox(height: 14),
            Row(
              children: _queues.map((q) {
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: q == _queues.last ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Icon(q.icon, size: 15, color: q.color),
                        const SizedBox(height: 3),
                        Text('${_count(q.key)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        Text(q.label,
                            style: const TextStyle(
                                color: Color(0xFFCBB6FF), fontSize: 9.5)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  // ── Pill tab bar ──────────────────────────────────────────────────────────
  Widget _tabBar() => Container(
        height: 44,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _queues.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final q = _queues[i];
            final sel = _tab.index == i;
            return GestureDetector(
              onTap: () => _tab.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: sel ? q.color : AppTheme.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: sel ? q.color : const Color(0xFFE5E7EB)),
                  boxShadow: sel
                      ? [BoxShadow(color: q.color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(q.icon,
                        size: 16,
                        color: sel ? Colors.white : q.color),
                    const SizedBox(width: 6),
                    Text(q.label,
                        style: TextStyle(
                            color: sel ? Colors.white : const Color(0xFF374151),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                          color: sel
                              ? Colors.white.withValues(alpha: 0.25)
                              : q.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${_count(q.key)}',
                          style: TextStyle(
                              color: sel ? Colors.white : q.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _queueList(_Queue q) {
    final items = (_queueData[q.key] as List?) ?? [];
    if (items.isEmpty) return _empty(q);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _jobCard(q, items[i] as Map<String, dynamic>, i),
      ),
    );
  }

  Widget _empty(_Queue q) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 110),
            Icon(q.icon, size: 52, color: q.color.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
            Center(
              child: Text('No jobs in the ${q.label} queue',
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _jobCard(_Queue q, Map<String, dynamic> m, int index) {
    final attempts = (m['attempts'] as List?) ?? [];
    final name = attempts.isNotEmpty
        ? (attempts.first['profile_name'] ?? 'Pin')
        : 'Pin #${m['location_group_id']}';
    final count = m['attempt_count'] ?? attempts.length;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0F0F172A), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Priority rank rail
            Container(
              width: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [q.color, q.color.withValues(alpha: 0.7)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('$name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        if (m['pay_rate'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text('\$${m['pay_rate']}',
                                style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 13, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            m['address']?.toString() ??
                                '${m['latitude']}, ${m['longitude']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chip(q.label, q.color),
                        const SizedBox(width: 6),
                        _chip('$count attempt${count == 1 ? '' : 's'}',
                            const Color(0xFF6B7280)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}
