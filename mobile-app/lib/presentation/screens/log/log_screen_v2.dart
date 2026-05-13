import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/app_config.dart';
import '../../../data/models/log_entry_model.dart';
import '../../providers/log_provider.dart';

class LogScreenV2 extends ConsumerStatefulWidget {
  const LogScreenV2({super.key});

  @override
  ConsumerState<LogScreenV2> createState() => _LogScreenV2State();
}

class _LogScreenV2State extends ConsumerState<LogScreenV2>
    with TickerProviderStateMixin {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceElevated = Color(0xFFFAFBFC);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF5B5BD6);
  static const Color _accentSoft = Color(0xFFEEEEFD);
  static const Color _rushRed = Color(0xFFDC2626);
  static const Color _rushRedSoft = Color(0xFFFEF2F2);
  static const Color _standardGreen = Color(0xFF059669);
  static const Color _standardGreenSoft = Color(0xFFECFDF5);
  static const Color _airportBlue = Color(0xFF0284C7);
  static const Color _airportBlueSoft = Color(0xFFEFF6FF);

  // ── State ─────────────────────────────────────────────────────────────────
  DateTime? _selectedDate;
  String? _selectedServiceType;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  late AnimationController _filterBadgeController;

  @override
  void initState() {
    super.initState();
    _filterBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _searchFocus.addListener(() {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _filterBadgeController.dispose();
    super.dispose();
  }

  // ── Computed ──────────────────────────────────────────────────────────────
  ({String? date, String? zipCode, String? status, String? search})
      get _filters => (
            date: _selectedDate != null
                ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                : null,
            zipCode: null,
            status: _selectedServiceType,
            search: _searchQuery.isEmpty ? null : _searchQuery,
          );

  bool get _hasFilters =>
      _selectedDate != null || _selectedServiceType != null;

  int get _filterCount {
    var n = 0;
    if (_selectedDate != null) n++;
    if (_selectedServiceType != null) n++;
    return n;
  }

  void _clearFilters() => setState(() {
        _selectedDate = null;
        _selectedServiceType = null;
      });

  // ── Time helpers ──────────────────────────────────────────────────────────
  String _relativeTime(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return ts;
    }
  }

  String _fullTime(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('MMM d, yyyy · h:mm a').format(
        DateTime.parse(ts).toLocal(),
      );
    } catch (_) {
      return ts;
    }
  }

  String _locationLabel(LogEntryModel log) {
    if (log.zipCode != null && log.zipCode!.isNotEmpty) {
      return 'ZIP ${log.zipCode}';
    }
    final lat = log.latitude;
    final lng = log.longitude;
    // Rough US city approximation from coordinates
    if (lat >= 32.5 && lat <= 33.0 && lng >= -117.5 && lng <= -116.8) {
      return 'San Diego, CA';
    }
    if (lat >= 33.7 && lat <= 34.3 && lng >= -118.7 && lng <= -117.9) {
      return 'Los Angeles, CA';
    }
    if (lat >= 37.6 && lat <= 37.9 && lng >= -122.6 && lng <= -122.2) {
      return 'San Francisco, CA';
    }
    if (lat >= 40.6 && lat <= 40.9 && lng >= -74.1 && lng <= -73.7) {
      return 'New York, NY';
    }
    return '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}';
  }

  // ── Section grouping ──────────────────────────────────────────────────────
  Map<String, List<LogEntryModel>> _groupByDate(List<LogEntryModel> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = <String, List<LogEntryModel>>{};
    for (final log in logs) {
      String key;
      try {
        final dt = DateTime.parse(log.timestamp ?? '').toLocal();
        final day = DateTime(dt.year, dt.month, dt.day);
        if (day == today) {
          key = 'Today';
        } else if (day == yesterday) {
          key = 'Yesterday';
        } else if (day.isAfter(weekAgo)) {
          key = 'Earlier This Week';
        } else {
          key = DateFormat('MMMM yyyy').format(dt);
        }
      } catch (_) {
        key = 'Earlier';
      }
      groups.putIfAbsent(key, () => []).add(log);
    }
    return groups;
  }

  // ── Service helpers ───────────────────────────────────────────────────────
  Color _svcColor(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return _rushRed;
      case 'airport':
        return _airportBlue;
      default:
        return _standardGreen;
    }
  }

  Color _svcSoftColor(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return _rushRedSoft;
      case 'airport':
        return _airportBlueSoft;
      default:
        return _standardGreenSoft;
    }
  }

  String _svcLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return 'Rush';
      case 'airport':
        return 'Airport';
      default:
        return 'Standard';
    }
  }

  // ── CSV + Share ───────────────────────────────────────────────────────────

  /// Build a CSV string from the current log entries
  String _buildCsv(List<LogEntryModel> logs) {
    final buf = StringBuffer();
    // Header row
    buf.writeln('ID,Timestamp,Profile,Service Type,ZIP Code,Latitude,Longitude,Note');
    for (final log in logs) {
      String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
      final profiles = (log.profiles != null && log.profiles!.isNotEmpty)
          ? log.profiles!.map((p) => p.name).join(' | ')
          : (log.profileName ?? '');
      buf.writeln([
        log.id,
        esc(log.timestamp != null
            ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(log.timestamp!).toLocal())
            : ''),
        esc(profiles),
        esc(log.serviceType),
        esc(log.zipCode),
        log.latitude.toStringAsFixed(6),
        log.longitude.toStringAsFixed(6),
        esc(log.note),
      ].join(','));
    }
    return buf.toString();
  }

  /// Write CSV to a temp file and return the path
  Future<String> _writeCsvFile(List<LogEntryModel> logs) async {
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/geotag-log-$dateStr.csv');
    await file.writeAsString(_buildCsv(logs));
    return file.path;
  }

  /// Download (save) CSV — shares as a file so iOS/Android can save it
  Future<void> _downloadCsv(List<LogEntryModel> logs) async {
    if (logs.isEmpty) {
      _showSnack('No records to export — adjust your filters first.');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      final path = await _writeCsvFile(logs);
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        subject: 'GeoTag Log — $dateStr',
        text: 'GeoTagging activity log — ${logs.length} records',
      );
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  /// Share as plain text (profile names, times, locations)
  Future<void> _shareLog(List<LogEntryModel> logs) async {
    if (logs.isEmpty) {
      _showSnack('No records to share — adjust your filters first.');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      final dateStr = DateFormat('MMM d, yyyy').format(DateTime.now());
      final lines = logs.take(50).map((log) {
        final profiles = (log.profiles != null && log.profiles!.isNotEmpty)
            ? log.profiles!.map((p) => p.name).join(', ')
            : (log.profileName ?? 'Unknown');
        final time = log.timestamp != null
            ? DateFormat('MMM d · h:mm a').format(DateTime.parse(log.timestamp!).toLocal())
            : '';
        final loc = _locationLabel(log);
        final svc = _svcLabel(log.serviceType);
        return '• $profiles  [$svc]\n  $time  ·  $loc${log.note != null && log.note!.isNotEmpty ? '\n  Note: ${log.note}' : ''}';
      }).join('\n\n');

      final text = 'GeoTagging Log — $dateStr\n${logs.length} record${logs.length == 1 ? '' : 's'}\n─────────────────────\n\n$lines${logs.length > 50 ? '\n\n…and ${logs.length - 50} more records. Download CSV for full list.' : ''}';

      await Share.share(
        text,
        subject: 'GeoTag Log — $dateStr',
      );
    } catch (e) {
      _showSnack('Share failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Filter sheet ──────────────────────────────────────────────────────────
  void _openFilterSheet() {
    HapticFeedback.lightImpact();
    var tempDate = _selectedDate;
    var tempType = _selectedServiceType;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ss(() {
                      tempDate = null;
                      tempType = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _canvas,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Reset all',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _inkMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'DATE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _inkSubtle,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: tempDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: _accent,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) ss(() => tempDate = picked);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: tempDate != null ? _accentSoft : _canvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tempDate != null ? _accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 17,
                        color: tempDate != null ? _accent : _inkSubtle,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tempDate != null
                              ? DateFormat('EEEE, MMMM d, yyyy')
                                  .format(tempDate!)
                              : 'Pick a date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: tempDate != null
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: tempDate != null ? _ink : _inkSubtle,
                          ),
                        ),
                      ),
                      if (tempDate != null)
                        GestureDetector(
                          onTap: () => ss(() => tempDate = null),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _inkSubtle.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: _inkMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'SERVICE TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _inkSubtle,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _filterPill(
                    label: 'All',
                    selected: tempType == null,
                    color: _accent,
                    onTap: () => ss(() => tempType = null),
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    label: 'Standard',
                    selected: tempType == 'standard',
                    color: _standardGreen,
                    onTap: () => ss(() => tempType = 'standard'),
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    label: 'Rush',
                    selected: tempType == 'rush',
                    color: _rushRed,
                    onTap: () => ss(() => tempType = 'rush'),
                  ),
                  const SizedBox(width: 8),
                  _filterPill(
                    label: 'Airport',
                    selected: tempType == 'airport',
                    color: _airportBlue,
                    onTap: () => ss(() => tempType = 'airport'),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _selectedDate = tempDate;
                      _selectedServiceType = tempType;
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterPill({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color : _canvas,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _inkMuted,
            ),
          ),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(logProvider(_filters));
    final logs = logAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          _buildHeader(logs),
          _buildSearchRow(),
          if (_hasFilters) _buildActiveFilters(),
          Expanded(child: _buildBody(logAsync)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(List<LogEntryModel> logs) => Container(
      color: _surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Activity',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.8,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedDate != null
                          ? DateFormat('EEEE, MMMM d')
                              .format(_selectedDate!)
                          : 'All field activity',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _inkSubtle,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Share button ──────────────────────────────────────
              _headerAction(
                icon: Icons.ios_share_rounded,
                tooltip: 'Share',
                onTap: () => _shareLog(logs),
              ),
              const SizedBox(width: 6),
              // ── Download CSV button ───────────────────────────────
              _headerAction(
                icon: Icons.download_rounded,
                tooltip: 'Download CSV',
                active: true,
                onTap: () => _downloadCsv(logs),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );

  Widget _headerAction({
    required IconData icon,
    required VoidCallback onTap, String? tooltip,
    bool active = false,
  }) {
    final widget = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? _accentSoft : _canvas,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? _accent : _inkMuted,
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: widget);
    }
    return widget;
  }

  // ── Search ────────────────────────────────────────────────────────────────
  Widget _buildSearchRow() => Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _searchFocused ? _accent : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: _searchFocused
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(
            fontSize: 15,
            color: _ink,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Search profiles, notes, locations…',
            hintStyle: const TextStyle(
              color: _inkSubtle,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: _searchFocused ? _accent : _inkSubtle,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Clear button — only when typing
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() => _searchQuery = '');
                        _searchController.clear();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _inkSubtle.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: _inkMuted,
                        ),
                      ),
                    ),
                  // Filter icon with badge
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _hasFilters ? _accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 19,
                            color: _hasFilters ? _accent : _inkSubtle,
                          ),
                        ),
                        if (_filterCount > 0)
                          Positioned(
                            top: -2,
                            right: 6,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$_filterCount',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleXY(
                                  begin: 0.8,
                                  end: 1.0,
                                  duration: 600.ms,
                                  curve: Curves.easeInOut,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 0,
              vertical: 13,
            ),
          ),
        ),
      ),
    );

  // ── Active filter chips ───────────────────────────────────────────────────
  Widget _buildActiveFilters() => Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedDate != null)
                    _activeChip(
                      label: DateFormat('MMM d').format(_selectedDate!),
                      icon: Icons.calendar_today_rounded,
                      color: _accent,
                      onRemove: () => setState(() => _selectedDate = null),
                    ),
                  if (_selectedServiceType != null) ...[
                    if (_selectedDate != null) const SizedBox(width: 6),
                    _activeChip(
                      label: _svcLabel(_selectedServiceType),
                      icon: Icons.label_rounded,
                      color: _svcColor(_selectedServiceType),
                      onRemove: () =>
                          setState(() => _selectedServiceType = null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _clearFilters,
            child: const Text(
              'Clear',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _activeChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onRemove,
  }) =>
      Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 5, bottom: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, size: 10, color: color),
              ),
            ),
          ],
        ),
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(AsyncValue<List<LogEntryModel>> logAsync) => logAsync.when(
      loading: _buildSkeleton,
      error: (err, _) => _buildError(err),
      data: (logs) {
        if (logs.isEmpty) return _buildEmpty();
        return _buildGroupedList(logs);
      },
    );

  // ── Skeleton loader ───────────────────────────────────────────────────────
  Widget _buildSkeleton() => ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFE5E7EB),
          highlightColor: const Color(0xFFF9FAFB),
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );

  // ── Grouped list ──────────────────────────────────────────────────────────
  Widget _buildGroupedList(List<LogEntryModel> logs) {
    final groups = _groupByDate(logs);
    final sectionOrder = ['Today', 'Yesterday', 'Earlier This Week'];
    final orderedKeys = [
      ...sectionOrder.where(groups.containsKey),
      ...groups.keys.where((k) => !sectionOrder.contains(k)),
    ];

    return RefreshIndicator(
      color: _accent,
      backgroundColor: _surface,
      onRefresh: () async { ref.invalidate(logProvider(_filters)); },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: orderedKeys.fold<int>(
          0,
          (sum, k) => sum + 1 + (groups[k]?.length ?? 0),
        ),
        itemBuilder: (context, flatIndex) {
          var cursor = 0;
          for (final key in orderedKeys) {
            final items = groups[key]!;
            if (flatIndex == cursor) {
              return _buildSectionHeader(key, items.length);
            }
            cursor++;
            if (flatIndex < cursor + items.length) {
              final item = items[flatIndex - cursor];
              final localIdx = flatIndex - cursor;
              return _buildLogCard(item, localIdx)
                  .animate()
                  .fadeIn(
                    duration: 350.ms,
                    delay: Duration(milliseconds: localIdx * 40),
                  )
                  .slideY(
                    begin: 0.06,
                    end: 0,
                    duration: 350.ms,
                    delay: Duration(milliseconds: localIdx * 40),
                    curve: Curves.easeOut,
                  );
            }
            cursor += items.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSectionHeader(String label, int count) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _inkMuted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _separator,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _inkSubtle,
              ),
            ),
          ),
        ],
      ),
    );

  // ── Log card ──────────────────────────────────────────────────────────────
  Widget _buildLogCard(LogEntryModel log, int index) {
    final svcColor = _svcColor(log.serviceType);
    final svcSoft = _svcSoftColor(log.serviceType);
    final svcLabel = _svcLabel(log.serviceType);
    final isRush = (log.serviceType ?? '').toLowerCase() == 'rush';
    final imageUrl = '${AppConfig.apiBaseUrl}${log.imageUrl}';
    final location = _locationLabel(log);

    return GestureDetector(
      onTapDown: (_) => HapticFeedback.selectionClick(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
          // Rush gets a subtle left accent
          border: isRush
              ? const Border(
                  left: BorderSide(color: _rushRed, width: 3),
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Thumbnail ──────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: const Color(0xFFE5E7EB),
                          highlightColor: const Color(0xFFF9FAFB),
                          child: Container(
                            width: 60,
                            height: 60,
                            color: _canvas,
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: _canvas,
                          child: const Icon(
                            Icons.image_outlined,
                            color: _inkSubtle,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ── Info ───────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  log.profileName ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Service badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: svcSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  svcLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: svcColor,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Location row
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 13,
                                color: _inkSubtle,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _inkMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Timestamp
                          if (log.timestamp != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: _inkSubtle,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _relativeTime(log.timestamp),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _inkSubtle,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 2,
                                  height: 2,
                                  decoration: const BoxDecoration(
                                    color: _inkSubtle,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _fullTime(log.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _inkSubtle,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Note ────────────────────────────────────────────────
              if (log.note != null && log.note!.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.notes_rounded,
                          size: 12,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.note!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _inkMuted,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    final isFiltered = _hasFilters || _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: _accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 38,
                color: _accent,
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 20),
            Text(
              isFiltered ? 'No results' : 'No activity yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.4,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try adjusting your search or filters'
                  : 'Photos you upload will appear here',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _inkSubtle,
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 150.ms),
            if (isFiltered) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  _clearFilters();
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Clear all filters',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
            ],
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError(Object error) => Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _rushRedSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 38,
                color: _rushRed,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connection issue',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().replaceAll('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _inkSubtle,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.invalidate(logProvider(_filters));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
