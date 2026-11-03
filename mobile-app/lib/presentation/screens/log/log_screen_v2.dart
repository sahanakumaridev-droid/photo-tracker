import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/maps_launcher.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/profile_lifecycle.dart';
import '../../../data/models/company.dart';
import '../../../data/models/log_entry_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../../widgets/common/create_profile_dialog.dart';
import '../../widgets/common/pill_chip.dart';
import '../upload/attempt_draft_controller.dart';
import '../upload/attempt_limits.dart';

part 'log_screen_header_and_filters.dart';
part 'log_screen_cards.dart';

class LogScreenV2 extends ConsumerStatefulWidget {
  const LogScreenV2({super.key, this.initialCategory});

  /// F3 — pre-applied category filter when arriving from the Map's
  /// service-level filter (so the list view stays in sync with the map).
  final String? initialCategory;

  @override
  ConsumerState<LogScreenV2> createState() => _LogScreenV2State();
}

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _canvas = Color(0xFFF2F4F7);
const Color _surface = Color(0xFFFFFFFF);
const Color _surfaceElevated = Color(0xFFEEF1F5);
const Color _ink = Color(0xFF1A2130);
const Color _inkMuted = Color(0xFF5C6778);
const Color _inkSubtle = Color(0xFF8B95A5);
const Color _separator = Color(0xFFE3E7EE);
const Color _accent = Color(0xFF4A90E2);
const Color _accentSoft = Color(0x1F4A90E2);
const Color _rushRed = Color(0xFFDC2626);
const Color _rushRedSoft = Color(0x26DC2626);
const Color _filterBar = Color(0xFFFFFFFF);

class _LogScreenV2State extends ConsumerState<LogScreenV2>
    with TickerProviderStateMixin {

  // ── State ─────────────────────────────────────────────────────────────────
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _selectedCategory; // null = all priority levels
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  late AnimationController _filterBadgeController;
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

  // Sends the selected entries via `/api/export/excel`: logged fields plus
  // a timestamp/geotag photo in the email — no spreadsheet.
  Future<void> _sendSelected(List<LogEntryModel> allLogs) async {
    final chosen =
        allLogs.where((l) => _selectedLogIds.contains(l.id)).toList();
    if (chosen.isEmpty) {
      _showSnack('Select at least one entry to send.');
      return;
    }
    await _exportExcel(chosen);
    if (mounted) setState(() => _selectionMode = false);
  }

  @override
  void initState() {
    super.initState();
    // F3 — arriving from the Map's service-level filter: pre-select the
    // matching category so the list view stays in sync with the map.
    final initialCat = widget.initialCategory;
    if (initialCat != null &&
        kPhotoCategories.any((c) => c.value == initialCat)) {
      _selectedCategory = initialCat;
    }
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
    // No explicit start time — let `date` carry the day-only filter.
    if (t == null) return null;
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
        // Service type is filtered client-side (the backend `status` field is
        // job lifecycle status, not service type) — see _applyClientFilters.
        status: null,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

  bool get _hasFilters =>
      _selectedDate != null || _selectedCategory != null;

  int get _filterCount {
    var n = 0;
    if (_selectedDate != null) n++;
    if (_selectedCategory != null) n++;
    return n;
  }

  void _clearFilters() => setState(() {
        _selectedDate = null;
        _startTime = null;
        _endTime = null;
        _selectedCategory = null;
      });

  /// Apply client-side filter for priority level (the backend doesn't
  /// reliably filter on it).
  List<LogEntryModel> _applyClientFilters(List<LogEntryModel> logs) {
    if (_selectedCategory == null) return logs;
    return logs.where((l) {
      if (_selectedCategory != null &&
          categoryOf(l.category).value != _selectedCategory) {
        return false;
      }
      return true;
    }).toList();
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
  /// Profiles with no attempt yet still belong in this list.
  List<LogEntryModel> _withProfilesWithoutAttempts(List<LogEntryModel> logs) {
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const [];
    final covered = <int>{
      for (final log in logs)
        if (log.profileId != null) log.profileId!,
    };
    final extras = <LogEntryModel>[];
    for (final p in profiles) {
      if (covered.contains(p.id)) continue;
      extras.add(LogEntryModel(
        id: -p.id,
        imageUrl: '',
        latitude: p.latitude ?? 0,
        longitude: p.longitude ?? 0,
        timestamp: (p.createdAt != null && p.createdAt!.trim().isNotEmpty)
            ? p.createdAt
            : '1970-01-01T00:00:00Z',
        address: p.address,
        profileId: p.id,
        profileName: p.name,
        serviceType: p.serviceType,
        category: p.serviceType,
        fileNumber: p.fileNumber,
        profiles: [p],
        attemptStatus: 'pending',
      ));
    }
    return [...extras, ...logs];
  }

  Map<String, List<LogEntryModel>> _groupByDate(List<LogEntryModel> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    // One card per profile. Photo files can carry old camera dates, which
    // otherwise split the same profile across two month sections.
    final newest = <String, LogEntryModel>{};
    for (final log in logs) {
      final profileKey = log.profileId?.toString() ??
          log.profileName ??
          log.id.toString();
      final prev = newest[profileKey];
      if (prev == null ||
          (log.timestamp ?? '').compareTo(prev.timestamp ?? '') > 0) {
        newest[profileKey] = log;
      }
    }

    final groups = <String, List<LogEntryModel>>{};
    for (final log in newest.values) {
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

  // ── F11: Excel export with saved recipients ───────────────────────────────
  // Every export — full list or a hand-picked selection — embeds the latest
  // (watermarked) photo per profile; there's no distinction between them.
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
          title: const Text('Email export'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${logs.length} record(s) with photo',
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
                    deleteIcon: const Icon(CupertinoIcons.xmark, size: 16),
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
                    icon: const Icon(CupertinoIcons.plus_circle_fill, color: _accent),
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
                child: const Text('Send')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    if (selected.isEmpty) {
      _showSnack('Select at least one recipient.');
      return;
    }

    _showSnack('Sending export email…');
    try {
      // Profile-list export schema (matches backend _EXPORT_COLUMNS_LIST):
      // file_number | name | date_time | priority_level | address | notes
      // Manual selection additionally embeds each profile's most recent photo
      // (watermarked) via `photo_id` + include_photo.
      // One row per profile, keeping that profile's most recent record.
      final byProfile = <String, LogEntryModel>{};
      for (final log in logs) {
        final key = (log.profileId ?? 'p${log.id}').toString();
        final cur = byProfile[key];
        if (cur == null ||
            (log.timestamp ?? '').compareTo(cur.timestamp ?? '') > 0) {
          byProfile[key] = log;
        }
      }
      final records = byProfile.values.map((log) {
        final dateTime = log.timestamp != null
            ? DateFormat('yyyy-MM-dd HH:mm:ss')
                .format(DateTime.parse(log.timestamp!).toLocal())
            : '';
        final rec = <String, dynamic>{
          'file_number': log.fileNumber ?? log.profileId?.toString() ?? '',
          'name': log.profileName ?? '',
          'date_time': dateTime,
          'priority_level': categoryLabel(log.category),
          'address': formatStreetNameAndZip(
              address: log.address, zipCode: log.zipCode),
          'notes': log.note ?? '',
          'coordinates': formatCoordinates(log.latitude, log.longitude),
          'photo_id': log.id,
        };
        return rec;
      }).toList();
      final result = await api.exportExcel(
          recipients: selected.toList(),
          records: records,
          includePhoto: true);
      if (!mounted) return;
      _showSnack(result['file_base64'] != null
          ? 'Email isn\'t set up on the server yet.'
          : '✓ Export emailed to ${selected.length} recipient(s)');
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    }
  }

  // ── Filter sheet ──────────────────────────────────────────────────────────
  void _openFilterSheet() {
    HapticFeedback.lightImpact();
    var tempDate = _selectedDate;
    var tempStart = _startTime;
    var tempEnd = _endTime;
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
                      Icon(CupertinoIcons.calendar, size: 17,
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
                            child: const Icon(CupertinoIcons.xmark, size: 12, color: _inkMuted),
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
                        icon: CupertinoIcons.clock,
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
                        icon: CupertinoIcons.clock,
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
                // ── PRIORITY LEVEL ────────────────────────────────────────
                const Text('PRIORITY LEVEL',
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
                child: const Icon(CupertinoIcons.xmark, size: 14, color: _inkMuted),
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
    // Apply the client-side filters (service type / category) here too, so the
    // header's Export button operates on EXACTLY the records shown in the list
    // below. Without this the export used the unfiltered set — selecting/seeing
    // 6 records but exporting more. _applyClientFilters is idempotent, so the
    // body re-applying it to the same data is harmless.
    final logs = _applyClientFilters(logAsync.valueOrNull ?? []);
    final userPos = ref.watch(currentLocationProvider).valueOrNull;

    return Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          _buildHeader(logs),
          _buildSearchRow(),
          if (_hasFilters) _buildActiveFilters(),
          Expanded(child: _buildBody(logAsync, userPos)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});
}
