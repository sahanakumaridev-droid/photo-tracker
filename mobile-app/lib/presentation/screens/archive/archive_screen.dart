import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../config/theme.dart';
import '../../../core/network/api_client.dart';

/// F10 — Job Archive (search / review / filter archived jobs).
/// Uses a virtualized ListView so it scales to large datasets.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

const _catColors = {
  'asap': Color(0xFFEF4444),
  'special': Color(0xFFF59E0B),
  'next_day': Color(0xFFEAB308),
  'standard': Color(0xFF10B981),
};

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  static const _levels = [
    ['', 'All'],
    ['asap', 'ASAP'],
    ['next_day', 'Next Day'],
    ['standard', 'Standard'],
    ['special', 'Special'],
  ];

  // F10 — job lifecycle filter shown above the service-level chips.
  static const _statuses = [
    ['active', 'Active'],
    ['completed', 'Completed'],
    ['archived', 'Archived'],
  ];

  String _search = '';
  String _level = '';
  String _status = 'active';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(apiServiceProvider).getArchive(
            search: _search.isEmpty ? null : _search,
            serviceLevel: _level.isEmpty ? null : _level,
            status: _status,
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _statusLabel => _statuses
      .firstWhere((s) => s[0] == _status, orElse: () => _statuses[0])[1];

  Color _color(String? cat) =>
      _catColors[(cat ?? 'standard').toLowerCase()] ?? _catColors['standard']!;

  int get _totalPay =>
      _rows.fold(0, (s, r) => s + ((r['pay_rate'] as int?) ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Archive'),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // F10 — job lifecycle filter (Active / Completed / Archived)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: _statuses.map((s) {
                final sel = _status == s[0];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s[1]),
                    selected: sel,
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.white,
                    labelStyle: TextStyle(
                        color: sel ? Colors.white : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                    side: BorderSide(
                        color: sel
                            ? AppTheme.primary
                            : const Color(0xFFE5E7EB)),
                    onSelected: (_) {
                      setState(() => _status = s[0]);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Premium stat header
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF334155)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x220F172A),
                        blurRadius: 18,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Row(
                  children: [
                    _stat('${_rows.length}', '$_statusLabel jobs',
                        CupertinoIcons.archivebox_fill),
                    Container(width: 1, height: 38, color: Colors.white24),
                    _stat('\$$_totalPay', 'Total pay', CupertinoIcons.money_dollar_circle_fill),
                  ],
                ),
              ),
            ),
          // Search (sticky above the list)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search ${_statusLabel.toLowerCase()} jobs…',
                prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: AppTheme.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          // Filter chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _levels.map((l) {
                final sel = _level == l[0];
                final c = l[0].isEmpty ? AppTheme.primary : _color(l[0]);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l[1]),
                    selected: sel,
                    selectedColor: c,
                    backgroundColor: AppTheme.white,
                    labelStyle: TextStyle(
                        color: sel ? Colors.white : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5),
                    side: BorderSide(
                        color: sel ? c : const Color(0xFFE5E7EB)),
                    onSelected: (_) {
                      setState(() => _level = l[0]);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Result count bar
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Text(
                      '${_rows.length} ${_statusLabel.toLowerCase()} '
                      'job${_rows.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                  const Spacer(),
                  if (_totalPay > 0)
                    Text('\$$_totalPay total',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10B981))),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                            'No ${_statusLabel.toLowerCase()} jobs found.',
                            style: const TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _row(_rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon) => Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22)),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 11)),
              ],
            ),
          ],
        ),
      );

  Widget _row(Map<String, dynamic> r) {
    final cat = (r['category'] ?? 'standard').toString();
    final c = _color(cat);
    final img = r['image_url'] as String?;
    return Material(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/photo/${r['id']}').then((_) => _load()),
        child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEDF4)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Category color stripe
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: c,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: img != null
                    ? CachedNetworkImage(
                        imageUrl: img.startsWith('http')
                            ? img
                            : '${AppConfig.apiBaseUrl}$img',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 52,
                          height: 52,
                          color: const Color(0xFFF3F4F6),
                        ),
                        errorWidget: (_, __, ___) => _imgFallback(),
                      )
                    : _imgFallback(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['profile_name']?.toString() ?? 'Pin',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(r['address']?.toString() ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(cat.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: c)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (r['pay_rate'] != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text('\$${r['pay_rate']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF10B981))),
                ),
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _imgFallback() => Container(
        width: 52,
        height: 52,
        color: const Color(0xFFF1F5F9),
        child: const Icon(CupertinoIcons.photo_fill_on_rectangle_fill, color: Color(0xFF94A3B8)),
      );
}
