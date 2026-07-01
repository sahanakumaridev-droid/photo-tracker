import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/job_pdf.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../core/utils/maps_launcher.dart';
import '../../../data/models/photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';

class PhotoDetailScreen extends ConsumerStatefulWidget {
  const PhotoDetailScreen({required this.photoId, super.key});

  final int photoId;

  @override
  ConsumerState<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

/// Result of the export options dialog: what to export + where to send it.
class _ExportChoice {
  const _ExportChoice(this.options, {required this.email});
  final JobExportOptions options;
  final bool email; // true = email to recipients, false = share sheet
}

class _PhotoDetailScreenState extends ConsumerState<PhotoDetailScreen> {
  // ── Design tokens (matches HomeScreenV2) ─────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _rushRed = Color(0xFFDC2626);
  static const Color _standardGreen = Color(0xFF10B981);
  static const Color _airportBlue = Color(0xFF0284C7);

  bool _imageExpanded = false;

  // ── Live reverse-geocoded address (for photos that only have ZIP stored) ──
  String? _resolvedAddress;
  bool _resolvingAddress = false;

  /// Called once when the photo loads — if address is missing, fetch it live
  /// from the photo's stored lat/lng via Nominatim.
  Future<void> _resolveAddressIfNeeded(PhotoModel photo) async {
    final hasAddress = photo.address != null && photo.address!.isNotEmpty;
    if (hasAddress) return; // already stored — nothing to do

    if (_resolvingAddress) return;
    if (!mounted) return;

    setState(() => _resolvingAddress = true);
    try {
      final address = await LocationService.reverseGeocode(
        photo.latitude,
        photo.longitude,
      );
      if (mounted && address != null && address.isNotEmpty) {
        setState(() => _resolvedAddress = address);
      }
    } catch (_) {
      // Silently fail — fallback to ZIP shown below
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  // ── Edit state ────────────────────────────────────────────────────────────

  // ── Helpers ───────────────────────────────────────────────────────────────
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

  String _svcLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return 'ASAP';
      case 'airport':
        return 'Airport';
      default:
        return 'Standard';
    }
  }

  IconData _svcIcon(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush':
        return Icons.local_fire_department_rounded;
      case 'airport':
        return Icons.flight_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  // ── F10: job lifecycle status ─────────────────────────────────────────────
  static const _statusSteps = ['open', 'in_progress', 'completed', 'archived'];

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'completed':
        return _standardGreen;
      case 'archived':
        return const Color(0xFF6B7280);
      default:
        return _airportBlue;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'in_progress':
        return Icons.sync_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      case 'archived':
        return Icons.inventory_2_rounded;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'archived':
        return 'Archived';
      default:
        return 'Open';
    }
  }

  Future<void> _setStatus(PhotoModel photo, String status) async {
    final current = photo.status ?? 'open';
    if (status == current) return;
    HapticFeedback.mediumImpact();

    // Confirm every status change — forward OR backward — so an accidental
    // tap can't silently move a job (e.g. straight to Completed).
    final confirmed = await _confirmStatusChange(current, status);
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(updateStatusProvider((photo.id, status)).future);
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Status updated to ${_statusLabel(status)}'),
              backgroundColor: _statusColor(status),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              // One-tap revert to the prior status (no extra confirm).
              action: SnackBarAction(
                label: 'Undo',
                textColor: Colors.white,
                onPressed: () => _revertStatus(photo.id, current),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ));
      }
    }
  }

  /// Explicit undo from the snackbar — reverts straight to [previous] without
  /// re-confirming, since the user has just chosen to undo.
  Future<void> _revertStatus(int photoId, String previous) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(updateStatusProvider((photoId, previous)).future);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Reverted to ${_statusLabel(previous)}'),
              backgroundColor: _statusColor(previous),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ));
      }
    }
  }

  /// "Are you sure?" confirmation shown before any status change. Names both
  /// the old and the new status and whether it's moving forward or back.
  Future<bool?> _confirmStatusChange(String from, String to) {
    final fromIdx = _statusSteps.indexOf(from);
    final toIdx = _statusSteps.indexOf(to);
    final goingBack = toIdx >= 0 && fromIdx >= 0 && toIdx < fromIdx;
    final toColor = _statusColor(to);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              goingBack ? Icons.undo_rounded : _statusIcon(to),
              color: toColor,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(goingBack ? 'Revert status?' : 'Change status?',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are changing this job from',
                style: TextStyle(fontSize: 14, color: _inkSubtle)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statusPill(from),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: _inkSubtle),
                ),
                _statusPill(to),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: toColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _statusColor(status).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _statusColor(status),
          ),
        ),
      );

  // ── Single-job export: detailed Excel + watermarked photo(s) ──────────────
  // One row per attempt (ID & Cntrl #, Date & Time, Service Ordered, Address,
  // Lat/Long, Job Status, Agent, Detailed Notes); the watermarked photos ride
  // along as separate attachments in the same email. Multi-job Excel export
  // (in the Log screen) is unchanged.
  Future<void> _exportJob(PhotoModel photo) async {
    final choice = await _showExportOptionsDialog();
    if (choice == null || !mounted) return;
    final opts = choice.options;

    // A "job" = all attempts for the same profile, newest-first.
    final all = ref.read(photosProvider).valueOrNull ?? const <PhotoModel>[];
    final pid = photo.profileId;
    final attempts = (pid == null
        ? <PhotoModel>[photo]
        : all.where((p) => p.profileId == pid).toList())
      ..sort((a, b) => (b.takenAt ?? b.timestamp ?? '')
          .compareTo(a.takenAt ?? a.timestamp ?? ''));
    if (attempts.isEmpty) attempts.add(photo);

    // Latest-only = just the most recent attempt; otherwise every attempt.
    final selected = opts.latestOnly ? attempts.take(1).toList() : attempts;
    final total = attempts.length;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Building service record…'),
        behavior: SnackBarBehavior.floating,
      ));

    try {
      final dio = ref.read(dioProvider);
      final agentEmail = ref.read(authProvider).email;
      final agentName = (agentEmail != null && agentEmail.contains('@'))
          ? agentEmail.split('@').first
          : (agentEmail ?? '');

      final records = <Map<String, dynamic>>[];
      // {filename, content_b64, mimetype} — the watermarked photos.
      final attachments = <Map<String, String>>[];

      for (final p in selected) {
        // Chronological attempt number (#1 = earliest) within the full job.
        final attemptNo = total - attempts.indexOf(p);
        records.add(_jobRecord(p, attemptNo, agentName));

        if (opts.includeImages) {
          try {
            final resp = await dio.get<List<int>>(
              p.imageUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            if (resp.data != null) {
              // Uploads store the RAW photo (the app shows the watermark as a
              // live overlay). For export we bake the caption into the file so
              // the downloaded/emailed photo carries a permanent stamp.
              final tmp = await getTemporaryDirectory();
              final raw = File('${tmp.path}/exp_${p.id}_$attemptNo.img');
              await raw.writeAsBytes(resp.data!);
              final stamped = await applyWatermark(
                raw,
                p.takenAt ?? p.timestamp ?? '',
                p.address ?? p.zipCode ?? '',
                latitude: p.latitude,
                longitude: p.longitude,
                serviceLabel: categoryLabel(p.category ?? p.serviceType),
                attemptNumber: attemptNo,
                agentName: agentName,
              );
              attachments.add({
                'filename': 'attempt_${attemptNo}_${p.id}.png',
                'content_b64': base64Encode(await stamped.readAsBytes()),
                'mimetype': 'image/png',
              });
            }
          } catch (_) {/* skip image on fetch failure */}
        }
      }

      final safeName = (photo.profileName ?? 'job')
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final baseName = 'service-record-$safeName';

      if (!mounted) return;
      if (choice.email) {
        await _emailJobRecord(photo, records, attachments, baseName,
            _jobHeader(photo, agentName), opts.latestOnly);
      } else {
        await _shareJobRecord(photo, records, attachments, baseName);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Export failed: '
              '${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  /// Builds one Excel row for an attempt, matching the client's column set:
  /// ID & Cntrl # · Date & Time · Service Ordered · Address · Lat/Long ·
  /// Job Status · Agent · Detailed Notes.
  Map<String, dynamic> _jobRecord(
      PhotoModel p, int attemptNo, String agentName) {
    final profileId = p.profileId?.toString() ?? '';
    final profileName = p.profileName ?? '';
    final idCtrl = profileId.isNotEmpty && profileName.isNotEmpty
        ? '$profileId / $profileName'
        : profileId.isNotEmpty
            ? profileId
            : profileName;

    final tsIso = p.takenAt ?? p.timestamp;
    final dateTime = tsIso != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(DateTime.parse(tsIso).toLocal())
        : '';

    // Address inline with ZIP when the ZIP isn't already part of it.
    var address = p.address ?? '';
    final zip = p.zipCode ?? '';
    if (address.isEmpty) {
      address = zip;
    } else if (zip.isNotEmpty && !address.contains(zip)) {
      address = '$address, $zip';
    }

    final note = (p.note ?? '').trim();
    return {
      'id_ctrl': idCtrl,
      'date_time': dateTime,
      'service_ordered': categoryLabel(p.category ?? p.serviceType),
      'address': address,
      'coordinates':
          '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
      'job_status': _statusLabel(p.status ?? 'open'),
      'agent': agentName,
      'completion_type': p.completionType ?? '',
      'served_to': p.servedTo ?? '',
      'detailed_notes': note.isEmpty ? 'Attempt #$attemptNo' : note,
    };
  }

  /// Rockstar service-record header for the email body, drawn from the most
  /// recent attempt ([photo]) of the job.
  Map<String, dynamic> _jobHeader(PhotoModel photo, String agentName) {
    var address = photo.address ?? '';
    final zip = photo.zipCode ?? '';
    if (address.isEmpty) {
      address = zip;
    } else if (zip.isNotEmpty && !address.contains(zip)) {
      address = '$address, $zip';
    }
    return {
      'service_name': photo.profileName ?? '',
      'dispatch_type': categoryLabel(photo.category ?? photo.serviceType),
      'status': _statusLabel(photo.status ?? 'open'),
      'agent': agentName,
      'address': address,
      'completion_type': photo.completionType ?? '',
      'served_to': photo.servedTo ?? '',
    };
  }

  /// Emails the Excel + photo attachments to chosen recipients (Dispatch /
  /// client), after letting the user pick from saved recipients + a one-off.
  Future<void> _emailJobRecord(
    PhotoModel photo,
    List<Map<String, dynamic>> records,
    List<Map<String, String>> attachments,
    String baseName,
    Map<String, dynamic> header,
    bool latestOnly,
  ) async {
    final api = ref.read(apiServiceProvider);
    var saved = <Map<String, dynamic>>[];
    try {
      saved = await api.getRecipients();
    } catch (_) {/* offline / not configured — user can still type one */}
    if (!mounted) return;

    final recipients = await _pickRecipients(saved);
    if (recipients == null || recipients.isEmpty || !mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Emailing service record…'),
        behavior: SnackBarBehavior.floating,
      ));
    try {
      final res = await api.exportJobExcel(
        recipients: recipients,
        records: records,
        attachments: attachments,
        subject: 'Service Record — ${photo.profileName ?? ''}',
        body: 'Service record for ${photo.profileName ?? 'this job'} attached.',
        baseName: baseName,
        header: header,
        latestOnly: latestOnly,
      );
      if (!mounted) return;
      final notConfigured = res['file_base64'] != null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(notConfigured
              ? 'Email isn\'t set up on the server yet — record generated.'
              : 'Service record emailed to ${recipients.length} '
                  'recipient${recipients.length > 1 ? 's' : ''}.'),
          backgroundColor: notConfigured ? null : _standardGreen,
          behavior: SnackBarBehavior.floating,
        ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Email failed: '
              '${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: _rushRed,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  /// Builds the Excel server-side (no recipients) and hands it to the OS share
  /// sheet together with the watermarked photos the app already fetched.
  Future<void> _shareJobRecord(
    PhotoModel photo,
    List<Map<String, dynamic>> records,
    List<Map<String, String>> attachments,
    String baseName,
  ) async {
    final api = ref.read(apiServiceProvider);
    final res = await api.exportJobExcel(
      recipients: const [],
      records: records,
      baseName: baseName,
    );
    if (!mounted) return;

    final files = <XFile>[];
    final b64 = res['file_base64'] as String?;
    if (b64 != null) {
      files.add(XFile.fromData(
        base64Decode(b64),
        name: (res['filename'] as String?) ?? '$baseName.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ));
    }
    for (final a in attachments) {
      files.add(XFile.fromData(
        base64Decode(a['content_b64']!),
        name: a['filename'],
        mimeType: a['mimetype'],
      ));
    }
    if (files.isEmpty) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Share.shareXFiles(
      files,
      subject: 'Service Record — ${photo.profileName ?? ''}',
    );
  }

  /// Recipient picker: tick any saved recipients and/or add a one-off email.
  Future<List<String>?> _pickRecipients(
      List<Map<String, dynamic>> saved) {
    final selected = <String>{};
    final customCtrl = TextEditingController();
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Email to',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (saved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('No saved recipients — add one below.',
                        style: TextStyle(fontSize: 13, color: _inkSubtle)),
                  ),
                ...saved.map((r) {
                  final email = (r['email'] ?? '').toString();
                  final label = (r['label'] ?? '').toString();
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: selected.contains(email),
                    title: Text(label.isEmpty ? email : label),
                    subtitle: label.isEmpty ? null : Text(email),
                    onChanged: (v) => setLocal(() {
                      if (v ?? false) {
                        selected.add(email);
                      } else {
                        selected.remove(email);
                      }
                    }),
                  );
                }),
                TextField(
                  controller: customCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Add another email…',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final out = {...selected};
                final custom = customCtrl.text.trim();
                if (custom.contains('@')) out.add(custom);
                Navigator.pop(ctx, out.toList());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  /// Lets the user pick: latest attempt only vs all attempts, whether to embed
  /// the watermarked images, and the destination (Share sheet or email to saved
  /// recipients). Returns null on cancel.
  Future<_ExportChoice?> _showExportOptionsDialog() {
    var latestOnly = false;
    var includeImages = true;
    return showDialog<_ExportChoice>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Export service record',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Latest attempt only'),
                subtitle: const Text('Off = include every attempt'),
                value: latestOnly,
                onChanged: (v) => setLocal(() => latestOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include photos'),
                subtitle: const Text('Off = text-only record'),
                value: includeImages,
                onChanged: (v) => setLocal(() => includeImages = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            // Email straight to saved recipients (Dispatch / client).
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                ctx,
                _ExportChoice(
                  JobExportOptions(
                      latestOnly: latestOnly, includeImages: includeImages),
                  email: true,
                ),
              ),
              icon: const Icon(Icons.email_outlined, size: 16),
              style: OutlinedButton.styleFrom(foregroundColor: _accent),
              label: const Text('Email…'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(
                ctx,
                _ExportChoice(
                  JobExportOptions(
                      latestOnly: latestOnly, includeImages: includeImages),
                  email: false,
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded, size: 16),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              label: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTs(String? ts) {
    if (ts == null) {
      return 'Unknown date';
    }
    try {
      final dt = DateTime.parse(ts).toLocal();
      return DateFormat('EEEE, MMMM d, yyyy • h:mm a').format(dt);
    } on FormatException {
      return ts;
    }
  }

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  // F6 — is the photo still inside the 10-min edit window (anchored to creation)?
  bool _withinTsWindow(PhotoModel photo) {
    final anchor = photo.createdAt ?? photo.takenAt ?? photo.timestamp;
    if (anchor == null) return false;
    try {
      final created = DateTime.parse(anchor).toUtc();
      return DateTime.now().toUtc().difference(created) <=
          const Duration(minutes: 10);
    } on FormatException {
      return false;
    }
  }

  // F6 — pick a new date + time and save it (server re-checks the 10-min window)
  Future<void> _editTimestamp(PhotoModel photo) async {
    HapticFeedback.lightImpact();
    final current =
        DateTime.tryParse(photo.timestamp ?? '')?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ref.read(
        editTimestampProvider((photo.id, picked.toUtc().toIso8601String()))
            .future,
      );
      ref.invalidate(photosProvider);
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timestamp updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFDC2626),
        ));
      }
    }
  }

  PhotoModel? _findPhoto(List<PhotoModel> photos) {
    final matches = photos.where((p) => p.id == widget.photoId);
    return matches.isEmpty ? null : matches.first;
  }

  // ── Edit actions ──────────────────────────────────────────────────────────

  void _showEditSheet(PhotoModel photo) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditPhotoSheet(photo: photo, parentRef: ref),
    );
  }

  // ── Map / clipboard actions ───────────────────────────────────────────────
  Future<void> _openInMaps(PhotoModel photo) async {
    // Prefer the human-readable address (behaves like pasting it into Maps);
    // fall back to coordinates when no address is available.
    final address = photo.address ?? _resolvedAddress;
    final launched = await MapsLauncher.openLocation(
      address: address,
      lat: photo.latitude,
      lng: photo.longitude,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open Maps'),
          backgroundColor: _accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _copyCoords(double lat, double lng) {
    Clipboard.setData(ClipboardData(text: '$lat, $lng'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coordinates copied to clipboard'),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);

    return photosAsync.when(
      loading: _buildLoadingScaffold,
      error: _buildErrorScaffold,
      data: (photos) {
        final photo = _findPhoto(photos);
        if (photo == null) {
          return _buildNotFoundScaffold();
        }
        // Auto reverse-geocode if address is missing
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resolveAddressIfNeeded(photo),
        );
        return _buildDetailScaffold(photo);
      },
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoadingScaffold() => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildErrorScaffold(Object err, StackTrace _) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _rushRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 32,
                    color: _rushRed,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString().replaceAll('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: _inkSubtle),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(photosProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Not found ─────────────────────────────────────────────────────────────
  Widget _buildNotFoundScaffold() => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _backButton(context),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: _accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  size: 36,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Photo not found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This photo may have been deleted.',
                style: TextStyle(fontSize: 13, color: _inkSubtle),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: context.pop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );

  // ── Main detail scaffold ──────────────────────────────────────────────────
  Widget _buildDetailScaffold(PhotoModel photo) {
    final svcColor = _svcColor(photo.serviceType);
    final url = _fullUrl(photo.imageUrl);

    return Scaffold(
      backgroundColor: _canvas,
      body: CustomScrollView(
        slivers: [
          // ── Hero image app bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: _imageExpanded ? 420 : 300,
            pinned: true,
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            leading: _backButton(context, dark: false),
            actions: [
              // Export this job as a PDF service record
              IconButton(
                icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
                tooltip: 'Export service record (PDF)',
                onPressed: () => _exportJob(photo),
              ),
              // Edit photo
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                tooltip: 'Edit photo',
                onPressed: () => _showEditSheet(photo),
              ),
              // Expand/collapse image
              IconButton(
                icon: Icon(
                  _imageExpanded
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _imageExpanded = !_imageExpanded);
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _imageExpanded = !_imageExpanded);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black87,
                        child: const Center(
                          child: Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white38,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                    // Photo ID badge (top-right, clear of the caption below)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#${photo.id}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Live watermark caption drawn from the photo's metadata
                    // (date / address / coordinates / service) so EVERY photo
                    // shows it — including ones uploaded before the stamp was
                    // baked in. Includes its own bottom gradient for contrast.
                    WatermarkCaption(
                      takenAtIso: photo.takenAt ?? photo.timestamp,
                      address: photo.address ?? photo.zipCode ?? '',
                      latitude: photo.latitude,
                      longitude: photo.longitude,
                      serviceLabel:
                          categoryLabel(photo.category ?? photo.serviceType),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Detail content ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile name + service type row
                  _buildProfileHeader(photo, svcColor),
                  const SizedBox(height: 10),

                  // F10 — job lifecycle status
                  _buildStatusCard(photo),
                  const SizedBox(height: 10),

                  // Status summary (only when job is closed)
                  if (photo.status == 'completed' ||
                      photo.status == 'archived') ...[
                    _buildStatusSummaryCard(photo),
                    const SizedBox(height: 10),
                  ],

                  // Payout
                  if (photo.payRate != null) ...[
                    _buildInfoCard(
                      icon: Icons.attach_money,
                      label: 'Payout',
                      value: '\$${photo.payRate}',
                      iconColor: const Color(0xFF16A34A),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Info cards
                  _buildInfoCard(
                    icon: Icons.access_time_rounded,
                    label: 'Captured',
                    value: _formatTs(photo.timestamp),
                    iconColor: _accent,
                    trailing: _withinTsWindow(photo)
                        ? TextButton.icon(
                            onPressed: () => _editTimestamp(photo),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit'),
                            style: TextButton.styleFrom(
                              foregroundColor: _accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 0),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.lock_outlined,
                                size: 15, color: _inkSubtle),
                          ),
                  ),
                  const SizedBox(height: 10),

                  // Location card with map action
                  _buildLocationCard(photo),
                  const SizedBox(height: 10),

                  // Note card (if present)
                  if (photo.note != null && photo.note!.isNotEmpty) ...[
                    _buildInfoCard(
                      icon: Icons.description_outlined,
                      label: 'Note',
                      value: photo.note!,
                      iconColor: const Color(0xFF0284C7),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Profiles tags (if multiple)
                  if (photo.profiles != null && photo.profiles!.isNotEmpty)
                    _buildProfileTags(photo),

                  const SizedBox(height: 24),

                  // Delete button only — Edit is in the AppBar pencil icon
                  _buildDeleteButton(photo),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────
  Widget _buildProfileHeader(PhotoModel photo, Color svcColor) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: svcColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (photo.profileName ?? 'U')[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: svcColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.profileName ?? 'Unknown Profile',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        _svcIcon(photo.serviceType),
                        size: 13,
                        color: svcColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _svcLabel(photo.serviceType),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: svcColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── F10: job lifecycle status card ────────────────────────────────────────
  Widget _buildStatusCard(PhotoModel photo) {
    final current = photo.status ?? 'open';
    final currentIndex = _statusSteps.indexOf(current);
    final color = _statusColor(current);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_statusIcon(current), size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JOB STATUS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _inkSubtle,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _statusLabel(current),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              // Step counter badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${currentIndex + 1} / ${_statusSteps.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Stepper
          _buildJobStepper(currentIndex, photo),
          const SizedBox(height: 14),
          // Hint row
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app_rounded,
                    size: 13, color: _inkSubtle),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap any stage to change status — you\'ll be asked to confirm',
                    style: TextStyle(
                      fontSize: 11,
                      color: _inkSubtle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Horizontal stepper track
  Widget _buildJobStepper(int currentIndex, PhotoModel photo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _statusSteps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                // top: 19 centres the 2px line on the 40px circle (40/2 − 1)
                padding: const EdgeInsets.only(top: 19),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  height: 2,
                  decoration: BoxDecoration(
                    color: i <= currentIndex
                        ? _statusColor(_statusSteps[i - 1])
                        : const Color(0xFFE8ECF0),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          _buildStepNode(i, currentIndex, photo),
        ],
      ],
    );
  }

  // Individual step node (circle + label)
  Widget _buildStepNode(int index, int currentIndex, PhotoModel photo) {
    final step = _statusSteps[index];
    final isCompleted = index < currentIndex;
    final isActive = index == currentIndex;
    final isFuture = index > currentIndex;
    final stepColor = _statusColor(step);

    return GestureDetector(
      // Any stage is tappable now — forward, backward, or jump. The confirm
      // dialog in _setStatus guards against accidental changes.
      onTap: isActive ? null : () => _setStatus(photo, step),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? stepColor
                  : isCompleted
                      ? stepColor.withValues(alpha: 0.12)
                      : const Color(0xFFF2F4F7),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? stepColor
                    : isCompleted
                        ? stepColor.withValues(alpha: 0.5)
                        : const Color(0xFFDDE2E8),
                width: isActive ? 0 : 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: stepColor.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : _statusIcon(step),
              size: 18,
              color: isActive
                  ? Colors.white
                  : isCompleted
                      ? stepColor
                      : const Color(0xFFB0B8C4),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: 58,
            child: Text(
              _statusLabel(step),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? stepColor
                    : isFuture
                        ? const Color(0xFFB0B8C4)
                        : _inkMuted,
                height: 1.25,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Status summary (shown when job is completed / archived) ──────────────
  Widget _buildStatusSummaryCard(PhotoModel photo) {
    final steps = [
      _SummaryStep(
        status: 'open',
        label: 'Opened',
        icon: Icons.radio_button_unchecked,
        timestamp: photo.createdAt ?? photo.timestamp,
        color: _airportBlue,
      ),
      const _SummaryStep(
        status: 'in_progress',
        label: 'In Progress',
        icon: Icons.sync_rounded,
        timestamp: null,
        color: Color(0xFFF59E0B),
      ),
      _SummaryStep(
        status: 'completed',
        label: 'Completed',
        icon: Icons.check_circle_rounded,
        timestamp: photo.completedAt,
        color: _standardGreen,
      ),
      if (photo.status == 'archived')
        const _SummaryStep(
          status: 'archived',
          label: 'Archived',
          icon: Icons.inventory_2_rounded,
          timestamp: null,
          color: _inkSubtle,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _standardGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.format_list_bulleted_rounded,
                    size: 18, color: _standardGreen),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STATUS SUMMARY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _inkSubtle,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Full job lifecycle',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Timeline rows
          for (int i = 0; i < steps.length; i++) ...[
            _buildSummaryRow(steps[i], isLast: i == steps.length - 1),
          ],
          // Closing line item — a distinct entry added when the job closes,
          // summarising how it was closed (payout, closing note, time).
          if (photo.status == 'completed' || photo.status == 'archived')
            _buildClosingLineItem(photo),
        ],
      ),
    );
  }

  // Distinct closing summary appended on close — relates the lifecycle to the
  // concrete outcome of the job (what was paid, any closing note).
  Widget _buildClosingLineItem(PhotoModel photo) {
    final isArchived = photo.status == 'archived';
    final details = <String>[];
    if (photo.payRate != null) details.add('Payout \$${photo.payRate}');
    if (photo.note != null && photo.note!.trim().isNotEmpty) {
      details.add(photo.note!.trim());
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isArchived ? Icons.inventory_2_rounded : Icons.task_alt_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isArchived ? 'Job Closed & Archived' : 'Job Closed',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                    Text(
                      _formatTs(photo.completedAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: _inkMuted,
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join('  •  '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _inkMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(_SummaryStep step, {required bool isLast}) {
    final formattedTs = step.timestamp != null
        ? _formatTs(step.timestamp)
        : '—';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: icon + vertical connector
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: step.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, size: 17, color: step.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _separator,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Right: label + timestamp
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: step.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formattedTs,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Generic info card ─────────────────────────────────────────────────────
  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    Widget? trailing,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _inkSubtle,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  // ── Location card ─────────────────────────────────────────────────────────
  Widget _buildLocationCard(PhotoModel photo) {
    final hasAddress = photo.address != null && photo.address!.isNotEmpty;
    final hasZip = photo.zipCode != null && photo.zipCode!.isNotEmpty;
    final coordsText = '${photo.latitude.toStringAsFixed(6)}, '
        '${photo.longitude.toStringAsFixed(6)}';

    // Priority: stored address → live-resolved address → ZIP → coords
    String locationDisplay;
    if (hasAddress) {
      final addr = photo.address!;
      if (hasZip && !addr.contains(photo.zipCode!)) {
        locationDisplay = '$addr, ${photo.zipCode}';
      } else {
        locationDisplay = addr;
      }
    } else if (_resolvedAddress != null) {
      // Live reverse-geocoded from lat/lng — full street address
      locationDisplay = _resolvedAddress!;
    } else if (_resolvingAddress) {
      locationDisplay = 'Fetching address…';
    } else if (hasZip) {
      locationDisplay = 'ZIP ${photo.zipCode}';
    } else {
      locationDisplay = coordsText;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOCATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _inkSubtle,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Human-readable address — tap to open in Maps
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _openInMaps(photo);
                      },
                      child: Text(
                        locationDisplay,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                          decoration: TextDecoration.underline,
                          decorationColor: _accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Always show raw coordinates below
                    Text(
                      coordsText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _inkMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: _separator, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.map_rounded,
                  label: 'Open in Maps',
                  color: _accent,
                  onTap: () => _openInMaps(photo),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy Coords',
                  color: const Color(0xFF0284C7),
                  onTap: () => _copyCoords(photo.latitude, photo.longitude),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );

  // ── Profile tags ──────────────────────────────────────────────────────────
  Widget _buildProfileTags(PhotoModel photo) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LINKED PROFILES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _inkSubtle,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photo.profiles!.map((p) {
                final color = _svcColor(p.serviceType);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  // ── Delete button ─────────────────────────────────────────────────────────
  Widget _buildDeleteButton(PhotoModel photo) => GestureDetector(
        onTap: () => _confirmDelete(photo),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _rushRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _rushRed.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: _rushRed),
              SizedBox(width: 8),
              Text(
                'Delete Photo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _rushRed,
                ),
              ),
            ],
          ),
        ),
      );

  void _confirmDelete(PhotoModel photo) {
    HapticFeedback.mediumImpact();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Photo',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This photo will be permanently deleted. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(deletePhotoProvider(photo.id).future);
                if (mounted) {
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Photo deleted'),
                      backgroundColor: _rushRed,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } on Exception catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: _rushRed,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _rushRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Back button ───────────────────────────────────────────────────────────
  Widget _backButton(BuildContext context, {bool dark = true}) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          context.pop();
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: dark
                ? Colors.black.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.chevron_left_rounded,
            size: 16,
            color: dark ? _ink : Colors.white,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Photo Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditPhotoSheet extends ConsumerStatefulWidget {
  const _EditPhotoSheet({required this.photo, required this.parentRef});

  final PhotoModel photo;
  final WidgetRef parentRef;

  @override
  ConsumerState<_EditPhotoSheet> createState() => _EditPhotoSheetState();
}

class _EditPhotoSheetState extends ConsumerState<_EditPhotoSheet> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFDC2626);

  late final TextEditingController _noteController;
  late final TextEditingController _addressController;
  final _imagePicker = ImagePicker();

  bool _isSavingNote = false;
  bool _isSavingAddress = false;
  bool _isReplacingImage = false;
  bool _isFetchingAddress = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.photo.note ?? '');

    // Combine address + ZIP into one field: "123 Main St, Dallas, TX 75001"
    final addr = widget.photo.address ?? '';
    final zip  = widget.photo.zipCode ?? '';
    var combined = addr;
    if (zip.isNotEmpty && !addr.contains(zip)) {
      combined = addr.isNotEmpty ? '$addr, $zip' : zip;
    }
    _addressController = TextEditingController(text: combined);

    // If address is missing or only has ZIP, auto-fetch from coordinates
    final needsGeocode = addr.isEmpty ||
        (addr == zip) ||
        (addr.trim() == zip.trim());
    if (needsGeocode &&
        widget.photo.latitude != 0 &&
        widget.photo.longitude != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFetchAddress());
    }
  }

  /// Reverse-geocode the photo's coordinates and populate the address field.
  Future<void> _autoFetchAddress() async {
    if (!mounted) return;
    setState(() => _isFetchingAddress = true);
    try {
      final address = await LocationService.reverseGeocode(
        widget.photo.latitude,
        widget.photo.longitude,
      );
      if (mounted && address != null && address.isNotEmpty) {
        setState(() {
          _addressController.text = address;
        });
      }
    } catch (_) {
      // Silently fail — user can type manually
    } finally {
      if (mounted) setState(() => _isFetchingAddress = false);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ── Snack helper ──────────────────────────────────────────────────────────
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _errorRed : _successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Save note ─────────────────────────────────────────────────────────────
  Future<void> _saveNote() async {
    final note = _noteController.text.trim();
    HapticFeedback.mediumImpact();
    setState(() => _isSavingNote = true);
    try {
      // Call the API
      await widget.parentRef.read(
        updatePhotoNoteProvider((widget.photo.id, note)).future,
      );
      // Invalidate and wait for the provider to finish refreshing so the
      // detail screen rebuilds with the new note before the sheet closes.
      widget.parentRef.invalidate(photosProvider);
      await widget.parentRef.read(photosProvider.future);
      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Note saved');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  // ── Save address + ZIP (combined) ─────────────────────────────────────────
  Future<void> _saveAddress() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) {
      _snack('Please enter an address', isError: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _isSavingAddress = true);
    try {
      final zipMatch = RegExp(r'\b(\d{5}(?:-\d{4})?)\b').allMatches(raw);
      final zip = zipMatch.isNotEmpty ? zipMatch.last.group(0) ?? '' : '';

      await widget.parentRef.read(
        updatePhotoAddressProvider((widget.photo.id, raw, zip)).future,
      );
      // Invalidate and wait for refresh so the detail screen rebuilds
      // with the new address before the sheet closes.
      widget.parentRef.invalidate(photosProvider);
      await widget.parentRef.read(photosProvider.future);

      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Address saved');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingAddress = false);
    }
  }

  // ── Replace image ─────────────────────────────────────────────────────────
  Future<void> _replaceImage(ImageSource source) async {
    // Check permissions
    if (source == ImageSource.camera) {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        _snack('Camera access blocked. Enable it in Settings.', isError: true);
        return;
      }
      if (status.isDenied || status.isRestricted) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          _snack('Camera permission required.', isError: true);
          return;
        }
      }
    } else {
      final status = await Permission.photos.status;
      if (status.isPermanentlyDenied) {
        _snack('Photo library access blocked. Enable it in Settings.',
            isError: true);
        return;
      }
      if (!status.isGranted && !status.isLimited) {
        final result = await Permission.photos.request();
        if (!result.isGranted && !result.isLimited) {
          _snack('Photo library permission required.', isError: true);
          return;
        }
      }
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;

      HapticFeedback.mediumImpact();
      setState(() => _isReplacingImage = true);

      await widget.parentRef.read(
        replacePhotoImageProvider((widget.photo.id, picked.path)).future,
      );
      widget.parentRef.invalidate(photosProvider);

      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Photo updated successfully');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _snack(
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isReplacingImage = false);
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _separator,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Replace Photo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 16),
            _sourceOption(
              icon: Icons.camera_alt_rounded,
              label: 'Take a new photo',
              onTap: () {
                Navigator.pop(context);
                _replaceImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 10),
            _sourceOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                _replaceImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _accent),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Edit Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: _canvas,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Edit note ────────────────────────────────────────────
                  // NOTE FIRST — prevents accidental camera trigger when
                  // user taps the note field (was below Replace Photo before)
                  _label('Note'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [SentenceCaseInputFormatter()],
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Add a note…',
                      hintStyle: const TextStyle(color: _inkSubtle),
                      filled: true,
                      fillColor: _canvas,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _accent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _saveBtn(
                    label: 'Save Note',
                    isLoading: _isSavingNote,
                    onTap: _saveNote,
                  ),
                  const SizedBox(height: 20),

                  // ── Address + ZIP (combined single field) ─────────────────
                  Row(
                    children: [
                      _label('Address & ZIP'),
                      const Spacer(),
                      if (_isFetchingAddress)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _accent),
                            ),
                            SizedBox(width: 6),
                            Text('Locating…',
                                style: TextStyle(
                                    fontSize: 11, color: _accent)),
                          ],
                        )
                      else
                        GestureDetector(
                          onTap: _autoFetchAddress,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 13, color: _accent),
                              SizedBox(width: 4),
                              Text('Auto-fill',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _accent)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Include ZIP at the end — e.g. 123 Main St, Dallas, TX 75001',
                    style: TextStyle(fontSize: 11, color: _inkSubtle),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addressController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [TitleCaseInputFormatter()],
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: '123 Main St, Dallas, TX 75001',
                      hintStyle: const TextStyle(color: _inkSubtle),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(Icons.location_on_rounded,
                            size: 18, color: _inkSubtle),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      filled: true,
                      fillColor: _canvas,
                      contentPadding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _accent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _saveBtn(
                    label: 'Save Address',
                    isLoading: _isSavingAddress,
                    onTap: _saveAddress,
                  ),
                  const SizedBox(height: 24),

                  // ── Divider before destructive/replace actions ────────────
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 20),

                  // ── Edit location ────────────────────────────────────────
                  _sectionCard(
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFF6B7280),
                    title: 'Edit Location',
                    subtitle:
                        '${widget.photo.latitude.toStringAsFixed(5)}, ${widget.photo.longitude.toStringAsFixed(5)}',
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: _inkSubtle,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/edit-location', extra: widget.photo);
                    },
                  ),
                  const SizedBox(height: 10),

                  // ── Replace image — at the BOTTOM to avoid accidental taps
                  _sectionCard(
                    icon: Icons.camera_alt_rounded,
                    iconColor: _accent,
                    title: 'Replace Photo',
                    subtitle: 'Swap the image with a new one',
                    trailing: _isReplacingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : const Icon(
                            Icons.chevron_right_rounded,
                            color: _inkSubtle,
                          ),
                    onTap: _isReplacingImage ? null : _showImageSourcePicker,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _inkMuted,
          letterSpacing: 0.2,
        ),
      );

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.lightImpact();
            onTap();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _inkSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );

  Widget _saveBtn({
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: isLoading ? null : () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: isLoading
                ? _accent.withValues(alpha: 0.5)
                : _accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for status summary timeline rows
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStep {
  const _SummaryStep({
    required this.status,
    required this.label,
    required this.icon,
    required this.timestamp,
    required this.color,
  });

  final String status;
  final String label;
  final IconData icon;
  final String? timestamp;
  final Color color;
}
