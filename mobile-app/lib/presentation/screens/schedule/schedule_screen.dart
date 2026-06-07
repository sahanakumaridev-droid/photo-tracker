import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';

/// F4 — Service-level scheduling queues.
/// Tabbed by queue so large datasets stay navigable (one scroll list per tab).
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
  late final TabController _tab = TabController(length: _queues.length, vsync: this);
  Map<String, dynamic> _queueData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Schedule'),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            color: AppTheme.white,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelColor: AppTheme.black,
              unselectedLabelColor: const Color(0xFF9CA3AF),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: _queues.map((q) {
                final n = _count(q.key);
                return Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(q.icon, size: 16, color: q.color),
                      const SizedBox(width: 6),
                      Text(q.label),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                            color: q.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('$n',
                            style: TextStyle(
                                color: q.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 11)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: _queues.map(_queueList).toList(),
            ),
    );
  }

  Widget _queueList(_Queue q) {
    final items = (_queueData[q.key] as List?) ?? [];
    if (items.isEmpty) {
      return _empty(q);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _jobRow(q, items[i] as Map<String, dynamic>, i),
      ),
    );
  }

  Widget _empty(_Queue q) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Icon(q.icon, size: 48, color: q.color.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Center(
              child: Text('No jobs in ${q.label} queue',
                  style: const TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );

  Widget _jobRow(_Queue q, Map<String, dynamic> m, int index) {
    final attempts = (m['attempts'] as List?) ?? [];
    final name = attempts.isNotEmpty
        ? (attempts.first['profile_name'] ?? 'Pin')
        : 'Pin #${m['location_group_id']}';
    final count = m['attempt_count'] ?? attempts.length;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEDF4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Priority index chip
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: q.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: q.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                    m['address']?.toString() ??
                        '${m['latitude']}, ${m['longitude']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 3),
                  Text('$count attempt${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (m['pay_rate'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('\$${m['pay_rate']}',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}
