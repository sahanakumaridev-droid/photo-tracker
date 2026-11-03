part of 'photo_detail_screen.dart';

extension _PhotoDetailExportExt on _PhotoDetailScreenState {
  Future<void> _exportJob(PhotoModel photo, {bool email = false}) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(email ? 'Preparing export…' : 'Preparing photo…'),
        behavior: SnackBarBehavior.floating,
      ));

    try {
      final agentEmail = ref.read(authProvider).email;
      final agentName = (agentEmail != null && agentEmail.contains('@'))
          ? agentEmail.split('@').first
          : (agentEmail ?? '');

      final records = <Map<String, dynamic>>[
        _jobRecord(photo, 1, agentName),
      ];
      final photoIds = <int>[photo.id];
      final header = _jobHeader(photo, agentName);
      final safeName = (photo.profileName ?? 'job')
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final baseName = 'attempt-$safeName';

      if (!mounted) return;
      if (email) {
        await _emailJobRecord(photo, records, photoIds, baseName, header, true);
      } else {
        await _shareJobRecord(photo, records, photoIds, baseName);
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

    final note = (p.note ?? '').trim();
    return {
      'id_ctrl': idCtrl,
      'file_number': p.fileNumber ?? '',
      'name': profileName,
      'date_time': dateTime,
      'service_ordered': categoryLabel(p.category ?? p.serviceType),
      'priority_level': categoryLabel(p.category ?? p.serviceType),
      'address': formatStreetNameAndZip(address: p.address, zipCode: p.zipCode),
      'coordinates':
          formatCoordinates(p.latitude, p.longitude),
      'job_status': _statusLabel(p.status ?? 'open'),
      'agent': agentName,
      'completion_type': p.completionType ?? '',
      'served_to': p.servedTo ?? '',
      'detailed_notes': note.isEmpty ? 'Attempt #$attemptNo' : note,
      'notes': note,
    };
  }

  /// Single-profile service-record header for the email body: File Number,
  /// Name, Date & Time, Priority Level, Address — drawn from the specific
  /// attempt ([photo]) being exported.
  Map<String, dynamic> _jobHeader(PhotoModel photo, String agentName) {
    final tsIso = photo.takenAt ?? photo.timestamp;
    final dateTime = tsIso != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(DateTime.parse(tsIso).toLocal())
        : '';
    return {
      'file_number': photo.fileNumber ?? '',
      'name': photo.profileName ?? '',
      'date_time': dateTime,
      'priority_level': categoryLabel(photo.category ?? photo.serviceType),
      'address': formatStreetNameAndZip(address: photo.address, zipCode: photo.zipCode),
      'coordinates':
          formatCoordinates(photo.latitude, photo.longitude),
    };
  }

  /// Emails logged data + the stamped photo (no spreadsheet).
  Future<void> _emailJobRecord(
    PhotoModel photo,
    List<Map<String, dynamic>> records,
    List<int> photoIds,
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
        photoIds: photoIds,
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

  /// Returns a safe sharePositionOrigin rect for the iOS share sheet popover
  /// — required by share_plus or shareXFiles throws a PlatformException.
  Rect _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      return Rect.fromLTWH(
        offset.dx + size.width / 2 - 20,
        offset.dy + size.height - 80,
        40,
        40,
      );
    }
    final screen = MediaQuery.of(context).size;
    return Rect.fromLTWH(screen.width / 2 - 20, screen.height - 120, 40, 40);
  }

  /// Share the watermarked photo plus a text summary of the logged fields.
  /// Never includes a spreadsheet.
  Future<void> _shareJobRecord(
    PhotoModel photo,
    List<Map<String, dynamic>> records,
    List<int> photoIds,
    String baseName,
  ) async {
    final api = ref.read(apiServiceProvider);
    final res = await api.exportJobExcel(
      recipients: const [],
      records: records,
      photoIds: photoIds,
      baseName: baseName,
      header: _jobHeader(photo, ''),
      latestOnly: true,
    );
    if (!mounted) return;

    final files = <XFile>[];
    final photos = (res['photos'] as List?) ?? const [];
    for (final a in photos) {
      final m = (a as Map).cast<String, dynamic>();
      final content = m['content_b64'] as String?;
      if (content == null) continue;
      files.add(XFile.fromData(
        base64Decode(content),
        name: m['filename'] as String? ?? 'photo.png',
        mimeType: m['mimetype'] as String? ?? 'image/png',
      ));
    }
    if (files.isEmpty) {
      for (final id in photoIds) {
        try {
          final bytes = await api.getWatermarkedPhotoBytes(id);
          if (bytes == null || bytes.isEmpty) continue;
          files.add(XFile.fromData(
            bytes,
            name: 'attempt_$id.png',
            mimeType: 'image/png',
          ));
        } catch (_) {}
      }
    }
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not attach the photo for sharing.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }

    final rec = records.isNotEmpty ? records.first : <String, dynamic>{};
    final lines = <String>[
      if ((rec['name'] as String?)?.isNotEmpty == true) rec['name'] as String,
      if ((rec['file_number'] as String?)?.isNotEmpty == true)
        'File: ${rec['file_number']}',
      if ((rec['date_time'] as String?)?.isNotEmpty == true)
        rec['date_time'] as String,
      if ((rec['priority_level'] as String?)?.isNotEmpty == true)
        rec['priority_level'] as String,
      if ((rec['address'] as String?)?.isNotEmpty == true)
        rec['address'] as String,
      if ((rec['coordinates'] as String?)?.isNotEmpty == true)
        rec['coordinates'] as String,
      if ((rec['detailed_notes'] as String?)?.isNotEmpty == true)
        rec['detailed_notes'] as String,
    ];

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Share.shareXFiles(
      files,
      subject: 'Attempt — ${photo.profileName ?? ''}',
      text: lines.join('\n'),
      sharePositionOrigin: _shareOrigin(),
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

}
