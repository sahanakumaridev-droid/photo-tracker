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
import '../../../core/network/api_client.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/log_entry_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/log_provider.dart';
import '../../providers/photo_provider.dart';

class LogScreenV2 extends ConsumerStatefulWidget {
  const LogScreenV2({super.key});

  @override
  ConsumerState<LogScreenV2> createState() => _LogScreenV2State();
}

class _LogScreenV2State extends ConsumerState<LogScreenV2>
    with TickerProviderStateMixin {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F2F2);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceElevated = Color(0xFFFAFAFA);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _rushRed = Color(0xFFDC2626);
  static const Color _rushRedSoft = Color(0xFFFEF2F2);
  static const Color _standardGreen = Color(0xFF10B981);
  static const Color _standardGreenSoft = Color(0xFFD1FAE5);
  static const Color _airportBlue = Color(0xFF0284C7);
  static const Color _airportBlueSoft = Color(0xFFEFF6FF);
  // Filter bar — noticeably darker than the page canvas
  static const Color _filterBar = Color(0xFFD8DCE6);

  // ── State ─────────────────────────────────────────────────────────────────
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _selectedServiceType;
  String? _selectedCategory; // null = all categories
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  late AnimationController _filterBadgeController;
  // Export profile selection
  Set<int> _selectedExportProfileIds = {};

  // ── Multi-select export ──────────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<int> _selectedLogIds = {};

  void _toggleSelectionMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedLogIds.clear();
    });
  }

  void _toggleLogSelected(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedLogIds.add(id)) _selectedLogIds.remove(id);
    });
  }

  Future<void> _exportSelected(List<LogEntryModel> allLogs) async {
    final chosen =
        allLogs.where((l) => _selectedLogIds.contains(l.id)).toList();
    if (chosen.isEmpty) {
      _showSnack('Select at least one entry to export.');
      return;
    }
    await _downloadCsv(chosen);
    if (mounted) setState(() => _selectionMode = false);
  }

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
  /// Build ISO datetime strings for start/end when a date + time is selected.
  String? get _startTimeStr {
    if (_selectedDate == null) return null;
    final t = _startTime;
    if (t == null) return DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final dt = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      t.hour, t.minute,
    );
    return DateFormat("yyyy-MM-dd'T'HH:mm").format(dt);
  }

  String? get _endTimeStr {
    if (_selectedDate == null) return null;
    final t = _endTime;
    if (t == null) return null; // backend defaults to end-of-day when only date given
    final dt = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      t.hour, t.minute,
    );
    return DateFormat("yyyy-MM-dd'T'HH:mm").format(dt);
  }

  ({
    String? date,
    String? startTime,
    String? endTime,
    String? zipCode,
    String? status,
    String? search,
  }) get _filters => (
        date: (_selectedDate != null && _startTime == null && _endTime == null)
            ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
            : null,
        startTime: _startTimeStr,
        endTime: _endTimeStr,
        zipCode: null,
        status: _selectedServiceType,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

  bool get _hasFilters =>
      _selectedDate != null ||
      _selectedServiceType != null ||
      _selectedCategory != null;

  int get _filterCount {
    var n = 0;
    if (_selectedDate != null) n++;
    if (_selectedServiceType != null) n++;
    if (_selectedCategory != null) n++;
    return n;
  }

  void _clearFilters() => setState(() {
        _selectedDate = null;
        _startTime = null;
        _endTime = null;
        _selectedServiceType = null;
        _selectedCategory = null;
      });

  /// Apply the client-side category filter (the backend doesn't filter on it).
  List<LogEntryModel> _applyCategoryFilter(List<LogEntryModel> logs) {
    if (_selectedCategory == null) return logs;
    return logs
        .where((l) => categoryOf(l.category).value == _selectedCategory)
        .toList();
  }

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

  /// Always returns the raw lat/lng string for display alongside the address.
  String _coordsLabel(LogEntryModel log) =>
      '${log.latitude.toStringAsFixed(6)}, ${log.longitude.toStringAsFixed(6)}';

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

    // Deduplicate: one entry per profile per section, keep newest
    for (final key in groups.keys.toList()) {
      final seen = <String>{};
      final deduped = <LogEntryModel>[];
      final sorted = List<LogEntryModel>.from(groups[key]!)
        ..sort((a, b) {
          final aTs = a.timestamp ?? '';
          final bTs = b.timestamp ?? '';
          return bTs.compareTo(aTs);
        });
      for (final entry in sorted) {
        final profileKey = entry.profileName ?? entry.id.toString();
        if (!seen.contains(profileKey)) {
          seen.add(profileKey);
          deduped.add(entry);
        }
      }
      groups[key] = deduped;
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
    buf.writeln('ID,Timestamp,Profile,Service Type,Category,ZIP Code,Latitude,Longitude,Note');
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
        esc(categoryLabel(log.category)),
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

  /// Returns a safe sharePositionOrigin rect for iOS share sheet popover.
  /// Uses the widget's own RenderBox — falls back to screen centre-bottom.
  Rect _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero);
      final size   = box.size;
      // Use centre of the screen horizontally, near the bottom where buttons are
      return Rect.fromLTWH(
        offset.dx + size.width / 2 - 20,
        offset.dy + size.height - 80,
        40,
        40,
      );
    }
    // Hard fallback: centre of screen
    final screen = MediaQuery.of(context).size;
    return Rect.fromLTWH(screen.width / 2 - 20, screen.height - 120, 40, 40);
  }

  /// Download (save) CSV — shares as a file so iOS/Android can save it
  Future<void> _downloadCsv(List<LogEntryModel> logs) async {
    if (logs.isEmpty) {
      _showSnack('No records to export — adjust your filters first.');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      final path      = await _writeCsvFile(logs);
      final dateStr   = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final result    = await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        subject: 'GeoTag Log — $dateStr',
        text: 'GeoTagging activity log — ${logs.length} records',
        sharePositionOrigin: _shareOrigin(),
      );
      if (result.status == ShareResultStatus.success) {
        _showSnack('✓ CSV exported — ${logs.length} records');
      }
    } on PlatformException catch (e) {
      if (e.code != 'cancel') {
        _showSnack('Export failed: ${e.message ?? 'Please try again.'}');
      }
    } catch (_) {
      // dismissed or cancelled — no error shown
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

  // ── Export sheet — multi-select profiles ─────────────────────────────────
  void _openExportSheet(List<LogEntryModel> allLogs) {
    HapticFeedback.lightImpact();

    // Build unique profile list from current logs
    final profilesInLogs = <int, String>{};
    for (final log in allLogs) {
      if (log.profileId != null) {
        profilesInLogs[log.profileId!] = log.profileName ?? 'Unknown';
      }
      for (final p in log.profiles ?? <ProfileModel>[]) {
        profilesInLogs[p.id] = p.name;
      }
    }

    var tempSelected = Set<int>.from(_selectedExportProfileIds);
    final allIds = profilesInLogs.keys.toSet();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          // Filter logs by selected profiles (empty = all)
          final exportLogs = tempSelected.isEmpty
              ? allLogs
              : allLogs.where((log) {
                  if (log.profileId != null &&
                      tempSelected.contains(log.profileId)) {
                    return true;
                  }
                  return log.profiles
                          ?.any((p) => tempSelected.contains(p.id)) ??
                      false;
                }).toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ──────────────────────────────────────
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: _separator,
                      borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Title + record count ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Export Logs',
                      style: TextStyle(fontSize: 22,
                          fontWeight: FontWeight.w700, color: _ink,
                          letterSpacing: -0.5)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '${exportLogs.length} record${exportLogs.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600, color: _accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select which profiles to include in the export.\nLeave all unchecked to export everything.',
                  style: TextStyle(fontSize: 13, color: _inkSubtle, height: 1.4),
                ),
                const SizedBox(height: 20),
                // ── Select all / none header ─────────────────────────
                Row(children: [
                  const Text('FILTER BY PROFILE',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: _inkSubtle,
                        letterSpacing: 1.4)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => ss(() => tempSelected =
                        tempSelected.length == allIds.length
                            ? {}
                            : Set.from(allIds)),
                    child: Text(
                      tempSelected.length == allIds.length
                          ? 'Deselect all'
                          : 'Select all',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600, color: _accent)),
                  ),
                ]),
                const SizedBox(height: 10),
                // ── Scrollable profile checkboxes ────────────────────
                // Flexible so it shrinks when few profiles and
                // scrolls when the list is long — no overflow.
                Flexible(
                  child: profilesInLogs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No profiles in current results',
                            style: TextStyle(color: _inkSubtle, fontSize: 13)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: profilesInLogs.entries.map((e) =>
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.value,
                                style: const TextStyle(fontSize: 14,
                                    fontWeight: FontWeight.w500, color: _ink)),
                              subtitle: Text(
                                '${allLogs.where((l) => l.profileId == e.key || (l.profiles?.any((p) => p.id == e.key) ?? false)).length} records',
                                style: const TextStyle(fontSize: 12, color: _inkSubtle)),
                              value: tempSelected.contains(e.key),
                              activeColor: _accent,
                              onChanged: (v) => ss(() {
                                if (v == true) {
                                  tempSelected = {...tempSelected, e.key};
                                } else {
                                  tempSelected = tempSelected
                                      .where((id) => id != e.key)
                                      .toSet();
                                }
                              }),
                            ),
                          ).toList(),
                        ),
                ),
                const SizedBox(height: 16),
                const Divider(color: _separator),
                const SizedBox(height: 12),
                // ── Export — single option: Excel spreadsheet → email ──
                // (F11) Per spec, the only export path is an Excel sheet sent to
                // a saved/chosen recipient.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: exportLogs.isEmpty
                        ? null
                        : () {
                            setState(() => _selectedExportProfileIds =
                                tempSelected);
                            Navigator.pop(ctx);
                            _exportExcel(exportLogs);
                          },
                    icon: const Icon(Icons.grid_on_rounded, size: 16),
                    label: const Text('Export Excel → Email'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Records are exported as an Excel spreadsheet to your chosen email.',
                  style: TextStyle(fontSize: 11, color: _inkSubtle),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── F11: Excel export with saved recipients ───────────────────────────────
  Future<void> _exportExcel(List<LogEntryModel> logs) async {
    if (logs.isEmpty) {
      _showSnack('No records to export — adjust your filters first.');
      return;
    }
    final api = ref.read(apiServiceProvider);

    // Load saved recipients (F11 manager) so the user can pick from a dropdown.
    var recipients = <Map<String, dynamic>>[];
    try {
      recipients = await api.getRecipients();
    } catch (_) {}
    if (!mounted) return;

    final selected = <String>{};
    final addCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Export Excel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${logs.length} record(s) → .xlsx',
                  style: const TextStyle(fontSize: 13, color: _inkMuted)),
              const SizedBox(height: 12),
              if (recipients.isEmpty)
                const Text('No saved recipients — add one below.',
                    style: TextStyle(fontSize: 12, color: _inkSubtle)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recipients.map((r) {
                  final email = r['email'].toString();
                  final sel = selected.contains(email);
                  return InputChip(
                    label: Text(r['label']?.toString() ?? email),
                    selected: sel,
                    onSelected: (_) => ss(() {
                      sel ? selected.remove(email) : selected.add(email);
                    }),
                    onDeleted: () async {
                      final id = r['id'];
                      if (id is int) {
                        try { await api.deleteRecipient(id); } catch (_) {}
                      }
                      ss(() {
                        recipients.remove(r);
                        selected.remove(email);
                      });
                    },
                    deleteIcon: const Icon(Icons.close, size: 16),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: addCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'add@recipient.com',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: _accent),
                    onPressed: () async {
                      final email = addCtrl.text.trim();
                      if (!email.contains('@')) return;
                      try {
                        final r = await api.addRecipient(email: email);
                        ss(() {
                          recipients.add(r);
                          selected.add(email);
                          addCtrl.clear();
                        });
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send Excel')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    if (selected.isEmpty) {
      _showSnack('Select at least one recipient.');
      return;
    }

    _showSnack('Generating Excel…');
    try {
      final records = logs
          .map((log) => {
                'id': log.id,
                'timestamp': log.timestamp,
                'profile_name': log.profileName,
                'service_type': log.serviceType,
                'category': log.category,
                'address': log.address,
                'zip_code': log.zipCode,
                'latitude': log.latitude,
                'longitude': log.longitude,
                'note': log.note,
              })
          .toList();
      final result = await api.exportExcel(
          recipients: selected.toList(), records: records);
      if (!mounted) return;
      _showSnack(result['file_base64'] != null
          ? 'Email not configured — Excel generated on server'
          : '✓ Excel sent to ${selected.length} recipient(s)');
    } catch (e) {
      if (mounted) _showSnack('Excel export failed: $e');
    }
  }

  // ── Filter sheet ──────────────────────────────────────────────────────────
  void _openFilterSheet() {
    HapticFeedback.lightImpact();
    var tempDate = _selectedDate;
    var tempStart = _startTime;
    var tempEnd = _endTime;
    var tempType = _selectedServiceType;
    var tempCategory = _selectedCategory;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => SingleChildScrollView(
          child: Container(
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
                    width: 36, height: 4,
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
                    const Text('Filter',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          color: _ink, letterSpacing: -0.5)),
                    GestureDetector(
                      onTap: () => ss(() {
                        tempDate = null;
                        tempStart = null;
                        tempEnd = null;
                        tempType = null;
                        tempCategory = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _canvas, borderRadius: BorderRadius.circular(20)),
                        child: const Text('Reset all',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                              color: _inkMuted)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                // ── DATE ──────────────────────────────────────────────────
                const Text('DATE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _inkSubtle, letterSpacing: 1.4)),
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
                          colorScheme: const ColorScheme.light(primary: _accent)),
                        child: child!,
                      ),
                    );
                    if (picked != null) ss(() => tempDate = picked);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    decoration: BoxDecoration(
                      color: tempDate != null ? _accentSoft : _canvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tempDate != null ? _accent : Colors.transparent,
                        width: 1.5),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_rounded, size: 17,
                          color: tempDate != null ? _accent : _inkSubtle),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tempDate != null
                              ? DateFormat('EEEE, MMMM d, yyyy').format(tempDate!)
                              : 'Pick a date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: tempDate != null ? FontWeight.w600 : FontWeight.w400,
                            color: tempDate != null ? _ink : _inkSubtle),
                        ),
                      ),
                      if (tempDate != null)
                        GestureDetector(
                          onTap: () => ss(() {
                            tempDate = null;
                            tempStart = null;
                            tempEnd = null;
                          }),
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: _inkSubtle.withValues(alpha: 0.15),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 12, color: _inkMuted),
                          ),
                        ),
                    ]),
                  ),
                ),
                // ── TIME RANGE (only shown when a date is selected) ────────
                if (tempDate != null) ...[
                  const SizedBox(height: 16),
                  const Text('TIME RANGE (OPTIONAL)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: _inkSubtle, letterSpacing: 1.4)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _timePicker(
                        ctx: ctx,
                        label: 'Start time',
                        value: tempStart,
                        icon: Icons.schedule_rounded,
                        onPicked: (t) => ss(() => tempStart = t),
                        onClear: () => ss(() => tempStart = null),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _timePicker(
                        ctx: ctx,
                        label: 'End time',
                        value: tempEnd,
                        icon: Icons.schedule_rounded,
                        onPicked: (t) => ss(() => tempEnd = t),
                        onClear: () => ss(() => tempEnd = null),
                      ),
                    ),
                  ]),
                  // Quick presets
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _presetChip('Morning (8–12)', () => ss(() {
                        tempStart = const TimeOfDay(hour: 8, minute: 0);
                        tempEnd   = const TimeOfDay(hour: 12, minute: 0);
                      })),
                      const SizedBox(width: 8),
                      _presetChip('Afternoon (12–5)', () => ss(() {
                        tempStart = const TimeOfDay(hour: 12, minute: 0);
                        tempEnd   = const TimeOfDay(hour: 17, minute: 0);
                      })),
                      const SizedBox(width: 8),
                      _presetChip('All day', () => ss(() {
                        tempStart = null;
                        tempEnd   = null;
                      })),
                    ]),
                  ),
                ],
                const SizedBox(height: 28),
                // ── SERVICE TYPE ──────────────────────────────────────────
                const Text('SERVICE TYPE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _inkSubtle, letterSpacing: 1.4)),
                const SizedBox(height: 12),
                Row(children: [
                  _filterPill(label: 'All', selected: tempType == null,
                      color: _accent, onTap: () => ss(() => tempType = null)),
                  const SizedBox(width: 8),
                  _filterPill(label: 'Standard', selected: tempType == 'standard',
                      color: _standardGreen, onTap: () => ss(() => tempType = 'standard')),
                  const SizedBox(width: 8),
                  _filterPill(label: 'Rush', selected: tempType == 'rush',
                      color: _rushRed, onTap: () => ss(() => tempType = 'rush')),
                  const SizedBox(width: 8),
                  _filterPill(label: 'Airport', selected: tempType == 'airport',
                      color: _airportBlue, onTap: () => ss(() => tempType = 'airport')),
                ]),
                const SizedBox(height: 28),
                // ── CATEGORY ──────────────────────────────────────────────
                const Text('CATEGORY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _inkSubtle, letterSpacing: 1.4)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterPill(
                      label: 'All',
                      selected: tempCategory == null,
                      color: _accent,
                      onTap: () => ss(() => tempCategory = null),
                    ),
                    for (final c in kPhotoCategories)
                      _filterPill(
                        label: c.label,
                        selected: tempCategory == c.value,
                        color: c.color,
                        onTap: () => ss(() => tempCategory = c.value),
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
                        _startTime = tempStart;
                        _endTime = tempEnd;
                        _selectedServiceType = tempType;
                        _selectedCategory = tempCategory;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Apply',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                          letterSpacing: 0.2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timePicker({
    required BuildContext ctx,
    required String label,
    required TimeOfDay? value,
    required IconData icon,
    required ValueChanged<TimeOfDay> onPicked,
    required VoidCallback onClear,
  }) =>
      GestureDetector(
        onTap: () async {
          final picked = await showTimePicker(
            context: ctx,
            initialTime: value ?? TimeOfDay.now(),
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                colorScheme: const ColorScheme.light(primary: _accent)),
              child: child!,
            ),
          );
          if (picked != null) onPicked(picked);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: value != null ? _accentSoft : _canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value != null ? _accent : Colors.transparent, width: 1.5),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: value != null ? _accent : _inkSubtle),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value != null ? value.format(ctx) : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
                  color: value != null ? _accent : _inkSubtle),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded, size: 14, color: _inkMuted),
              ),
          ]),
        ),
      );

  Widget _presetChip(String label, VoidCallback onTap) => GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _canvas, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _separator)),
          child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: _inkMuted)),
        ),
      );

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
              // ── Select toggle ──
              if (logs.isNotEmpty)
                GestureDetector(
                  onTap: _toggleSelectionMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Text(_selectionMode ? 'Cancel' : 'Select',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                  ),
                ),
              const SizedBox(width: 2),
              // ── Export button — selected entries, or the profile sheet ──
              GestureDetector(
                onTap: _selectionMode
                    ? () => _exportSelected(logs)
                    : () => _openExportSheet(logs),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectionMode && _selectedLogIds.isEmpty
                        ? _inkSubtle
                        : _accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.ios_share_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                          _selectionMode
                              ? 'Export (${_selectedLogIds.length})'
                              : 'Export',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );

  // ── Search ────────────────────────────────────────────────────────────────
  Widget _buildSearchRow() => Container(
      color: _filterBar,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                                  end: 1,
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
      color: _filterBar,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedDate != null)
                    _activeChip(
                      label: _startTime != null || _endTime != null
                          ? '${DateFormat('MMM d').format(_selectedDate!)} '
                            '${_startTime?.format(context) ?? '00:00'}'
                            '–${_endTime?.format(context) ?? 'end'}'
                          : DateFormat('MMM d').format(_selectedDate!),
                      icon: Icons.calendar_today_rounded,
                      color: _accent,
                      onRemove: () => setState(() {
                        _selectedDate = null;
                        _startTime = null;
                        _endTime = null;
                      }),
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
                  if (_selectedCategory != null) ...[
                    if (_selectedDate != null || _selectedServiceType != null)
                      const SizedBox(width: 6),
                    _activeChip(
                      label: categoryOf(_selectedCategory).label,
                      icon: categoryOf(_selectedCategory).icon,
                      color: categoryOf(_selectedCategory).color,
                      onRemove: () =>
                          setState(() => _selectedCategory = null),
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
      data: (allLogs) {
        if (allLogs.isEmpty) return _buildEmpty();
        final logs = _applyCategoryFilter(allLogs);
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

  // ── Selection radio ────────────────────────────────────────────────────────
  Widget _selectCircle(bool selected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _accent : _inkSubtle,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : null,
      );

  // ── Log card ──────────────────────────────────────────────────────────────
  Widget _buildLogCard(LogEntryModel log, int index) {
    final svcColor = _svcColor(log.serviceType);
    final svcSoft = _svcSoftColor(log.serviceType);
    final svcLabel = _svcLabel(log.serviceType);
    final isRush = (log.serviceType ?? '').toLowerCase() == 'rush';
    final imageUrl = '${AppConfig.apiBaseUrl}${log.imageUrl}';
    final selected = _selectedLogIds.contains(log.id);

    return GestureDetector(
      onTap: _selectionMode
          ? () => _toggleLogSelected(log.id)
          : () => _showLogDetail(log),
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
          border: selected
              ? Border.all(color: _accent, width: 2)
              : isRush
                  ? const Border(left: BorderSide(color: _rushRed, width: 3))
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
                    // ── Selection radio (selection mode only) ──────────
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 20, right: 12),
                        child: _selectCircle(selected),
                      ),
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
                          // Category badge
                          Builder(builder: (_) {
                            final cat = categoryOf(log.category);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cat.softColor,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                    color: cat.color.withValues(alpha: 0.3)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(cat.icon, size: 11, color: cat.color),
                                const SizedBox(width: 4),
                                Text(cat.label,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: cat.color)),
                              ]),
                            );
                          }),
                          const SizedBox(height: 6),
                          // Location row
                          _LocationText(log: log),
                          const SizedBox(height: 2),
                          // Coordinates row — always shown below address
                          Row(
                            children: [
                              const Icon(
                                Icons.gps_fixed_rounded,
                                size: 12,
                                color: _inkSubtle,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _coordsLabel(log),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _inkSubtle,
                                    fontFamily: 'monospace',
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
              decoration: const BoxDecoration(
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

  // ── Log detail dialog ─────────────────────────────────────────────────────
  void _showLogDetail(LogEntryModel log) {
    HapticFeedback.selectionClick();
    final imageUrl = '${AppConfig.apiBaseUrl}${log.imageUrl}';
    final cat = categoryOf(log.category);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
        backgroundColor: _surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.82),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
                child: Row(children: [
                  const Expanded(
                    child: Text('GeoTag Details',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.4)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditLogDialog(log);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: _inkSubtle),
                  ),
                ]),
              ),
              const Divider(height: 1, color: _separator),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor: const Color(0xFFE5E7EB),
                            highlightColor: const Color(0xFFF9FAFB),
                            child: Container(height: 200, color: _canvas)),
                          errorWidget: (_, __, ___) => Container(
                            height: 200,
                            color: _canvas,
                            child: const Center(
                                child: Icon(Icons.image_outlined,
                                    size: 44, color: _inkSubtle))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: Text(log.profileName ?? 'Unknown',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                  letterSpacing: -0.4)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: cat.softColor,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: cat.color.withValues(alpha: 0.3))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(cat.icon, size: 13, color: cat.color),
                            const SizedBox(width: 5),
                            Text(cat.label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cat.color)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      _detailRow(Icons.access_time_rounded, 'Timestamp',
                          _fullTime(log.timestamp)),
                      const SizedBox(height: 14),
                      _LiveLocationRow(log: log),
                      const SizedBox(height: 6),
                      _detailRow(Icons.gps_fixed_rounded, 'Coordinates',
                          _coordsLabel(log),
                          isMono: true),
                      if (log.note != null && log.note!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('NOTE',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _inkMuted,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: _surfaceElevated,
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(log.note!,
                              style: const TextStyle(
                                  fontSize: 14.5, color: _ink, height: 1.5)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit dialog ─────────────────────────────────────────────────────────────
  void _showEditLogDialog(LogEntryModel log) {
    HapticFeedback.selectionClick();
    final addressCtrl = TextEditingController(text: log.address ?? '');
    final zipCtrl = TextEditingController(text: log.zipCode ?? '');
    final noteCtrl = TextEditingController(text: log.note ?? '');
    var selectedCat = categoryOf(log.category).value;
    var saving = false;

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
          isDense: true,
          filled: true,
          fillColor: _surfaceElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.5)),
        );

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 16),
          child: Text(t.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _inkMuted,
                  letterSpacing: 0.6)),
        );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
                  child: Row(children: [
                    const Expanded(
                      child: Text('Edit GeoTag',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.4)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: _inkSubtle),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: _separator),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label('Category'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kPhotoCategories.map((c) {
                            final sel = selectedCat == c.value;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ss(() => selectedCat = c.value);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? c.color : c.softColor,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                      color: sel
                                          ? c.color
                                          : c.color.withValues(alpha: 0.25),
                                      width: 1.5),
                                ),
                                child:
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(c.icon,
                                      size: 14,
                                      color: sel ? Colors.white : c.color),
                                  const SizedBox(width: 6),
                                  Text(c.label,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              sel ? Colors.white : c.color)),
                                ]),
                              ),
                            );
                          }).toList(),
                        ),
                        label('Address'),
                        TextField(
                            controller: addressCtrl,
                            style: const TextStyle(fontSize: 14, color: _ink),
                            decoration: deco('Street address')),
                        label('ZIP Code'),
                        TextField(
                            controller: zipCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 14, color: _ink),
                            decoration: deco('ZIP')),
                        label('Note'),
                        TextField(
                            controller: noteCtrl,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 14, color: _ink),
                            decoration: deco('Add a note (optional)')),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: _separator),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _inkMuted,
                          side: const BorderSide(color: _separator),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                ss(() => saving = true);
                                try {
                                  await ref.read(updatePhotoAddressProvider((
                                    log.id,
                                    addressCtrl.text.trim(),
                                    zipCtrl.text.trim(),
                                  )).future);
                                  await ref.read(updatePhotoNoteProvider((
                                    log.id,
                                    noteCtrl.text.trim(),
                                  )).future);
                                  await ref.read(updatePhotoCategoryProvider((
                                    log.id,
                                    selectedCat,
                                  )).future);
                                  ref.invalidate(logProvider(_filters));
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('GeoTag updated'),
                                          behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                } catch (e) {
                                  ss(() => saving = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text('Update failed: $e'),
                                          behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon, String label, String value, {bool isMono = false}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: _accentSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: _accent)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _inkSubtle,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _ink,
                        fontFamily: isMono ? 'monospace' : null)),
              ]),
        ),
      ]);
}

class _LocationText extends StatefulWidget {
  const _LocationText({required this.log});
  final LogEntryModel log;
  @override
  State<_LocationText> createState() => _LocationTextState();
}

class _LocationTextState extends State<_LocationText> {
  String? _resolvedAddress;
  bool _fetching = false;
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() async {
    final log = widget.log;
    if (log.address != null && log.address!.isNotEmpty) {
      final addr = log.address!;
      if (log.zipCode != null && log.zipCode!.isNotEmpty && !addr.contains(log.zipCode!)) {
        setState(() => _resolvedAddress = '$addr, ${log.zipCode}');
      } else {
        setState(() => _resolvedAddress = addr);
      }
      return;
    }
    if (log.zipCode != null && log.zipCode!.isNotEmpty) {
      setState(() => _resolvedAddress = 'ZIP ${log.zipCode}');
      return;
    }
    if (_fetching) return;
    _fetching = true;
    try {
      final addr = await LocationService.reverseGeocode(log.latitude, log.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _resolvedAddress = addr);
      }
    } catch (_) {}
    _fetching = false;
  }

  @override
  Widget build(BuildContext context) {
    final text = _resolvedAddress ?? '${widget.log.latitude.toStringAsFixed(4)}, ${widget.log.longitude.toStringAsFixed(4)}';
    return Row(children: [
      const Icon(Icons.location_on_rounded, size: 13, color: _inkSubtle),
      const SizedBox(width: 4),
      Expanded(child: Text(text,
        style: const TextStyle(fontSize: 13, color: _inkMuted, fontWeight: FontWeight.w500),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}

class _LiveLocationRow extends StatefulWidget {
  const _LiveLocationRow({required this.log});
  final LogEntryModel log;
  @override
  State<_LiveLocationRow> createState() => _LiveLocationRowState();
}

class _LiveLocationRowState extends State<_LiveLocationRow> {
  String? _resolved;
  bool _fetching = false;
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkSubtle = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() async {
    final log = widget.log;
    if (log.address != null && log.address!.isNotEmpty) {
      final addr = log.address!;
      if (log.zipCode != null && log.zipCode!.isNotEmpty && !addr.contains(log.zipCode!)) {
        setState(() => _resolved = '$addr, ${log.zipCode}');
      } else {
        setState(() => _resolved = addr);
      }
      return;
    }
    if (log.zipCode != null && log.zipCode!.isNotEmpty) {
      setState(() => _resolved = 'ZIP ${log.zipCode}');
      return;
    }
    if (_fetching) return;
    _fetching = true;
    try {
      final addr = await LocationService.reverseGeocode(log.latitude, log.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _resolved = addr);
      }
    } catch (_) {}
    _fetching = false;
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.location_on_rounded, size: 15, color: _inkSubtle),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Location',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _inkSubtle, letterSpacing: 0.3)),
            const SizedBox(height: 3),
            Text(_resolved ?? '${widget.log.latitude.toStringAsFixed(4)}, ${widget.log.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _ink)),
          ],
        ),
      ),
    ],
  );
}
