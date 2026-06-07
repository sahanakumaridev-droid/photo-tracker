import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';

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
  ];

  String _period = 'today';
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
        api.getEarnings(period: _period),
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

  String _money(dynamic n) => '\$${((n ?? 0) as num).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final daily = (_summary?['daily_totals'] as List?) ?? [];
    final payoutDays = (_payouts?['daily'] as List?) ?? [];
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _periods.map((p) {
                  final sel = _period == p[0];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p[1]),
                      selected: sel,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: sel ? Colors.white : AppTheme.black,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) {
                        setState(() => _period = p[0]);
                        _load();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  _metric('Total Earnings',
                      _money(_summary?['total_earnings']), AppTheme.success),
                  const SizedBox(width: 12),
                  _metric('Jobs Done',
                      '${_summary?['jobs_completed'] ?? 0}', AppTheme.primary),
                ],
              ),
              const SizedBox(height: 12),
              _metric('Average Per Job',
                  _money(_summary?['average_per_job']), AppTheme.warning,
                  full: true),
              const SizedBox(height: 20),
              _card(
                title: 'Earnings Trend',
                child: daily.isEmpty
                    ? const Text('No completed jobs in this period yet.',
                        style: TextStyle(color: Colors.grey))
                    : Column(
                        children: daily.map((d) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${d['date']}'),
                                Text(_money(d['amount']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _card(
                title:
                    'Payouts / Timesheets · ${_money(_payouts?['total_earnings'])} · ${_payouts?['total_jobs'] ?? 0} jobs',
                child: payoutDays.isEmpty
                    ? const Text('No closed jobs yet.',
                        style: TextStyle(color: Colors.grey))
                    : Column(
                        children: payoutDays.map((d) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('${d['date']}'),
                            subtitle: Text('${d['jobs']} job(s)'),
                            trailing: Text(_money(d['amount']),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.success)),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color, {bool full = false}) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
    return full ? SizedBox(width: double.infinity, child: card) : Expanded(child: card);
  }

  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
