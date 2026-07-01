import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/photo_model.dart';
import 'category.dart';

/// One service attempt feeding the single-job PDF export.
class JobAttempt {
  JobAttempt({
    required this.photo,
    this.imageBytes,
  });

  final PhotoModel photo;
  final Uint8List? imageBytes;
}

/// Options for the single-job export, mirroring the in-app dialog.
class JobExportOptions {
  const JobExportOptions({
    this.latestOnly = false,
    this.includeImages = true,
  });

  final bool latestOnly;
  final bool includeImages;
}

/// Builds a Rockstar-Processing–style single-job PDF: header card with the
/// profile/service/status/payment, then one block per attempt (newest first)
/// with a large watermarked image, timestamp, readable address, lat/long,
/// distance and notes.
///
/// [attempts] should be passed newest-first. [userLat]/[userLng] enable the
/// per-attempt distance line. Returns the written temp file.
Future<File> buildJobPdf({
  required String profileName,
  required String serviceLabel,
  required String jobStatusLabel,
  required List<JobAttempt> attempts,
  String? agentName,
  String? completionType,
  String? servedTo,
  int? payRateDollars,
  double? userLat,
  double? userLng,
  JobExportOptions options = const JobExportOptions(),
}) async {
  final doc = pw.Document();

  // Attempts are newest-first; number them chronologically (#1 = earliest).
  final total = attempts.length;
  final selected = options.latestOnly ? attempts.take(1).toList() : attempts;

  const accent = PdfColor.fromInt(0xFF7C3AED);
  const ink = PdfColor.fromInt(0xFF111111);
  const muted = PdfColor.fromInt(0xFF6B7280);

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(k,
                  style: pw.TextStyle(
                      fontSize: 9,
                      color: muted,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
              child: pw.Text(v.isEmpty ? '—' : v,
                  style: const pw.TextStyle(fontSize: 9, color: ink)),
            ),
          ],
        ),
      );

  final latest = attempts.isNotEmpty ? attempts.first.photo : null;
  final headerAddr = latest?.address ?? '';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(profileName,
                  style: const pw.TextStyle(fontSize: 9, color: muted)),
            ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted)),
      ),
      build: (ctx) => [
        // ── Title ──
        pw.Text('Service Record',
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: accent)),
        pw.SizedBox(height: 2),
        pw.Text(profileName,
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
        pw.SizedBox(height: 6),

        // ── Summary card ──
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF7F5FF),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              kv('Service Name', profileName),
              kv('Dispatch Type', serviceLabel),
              kv('Status', jobStatusLabel),
              if (agentName != null && agentName.isNotEmpty)
                kv('Agent', agentName),
              if (completionType != null && completionType.isNotEmpty)
                kv('Type', completionType),
              if (servedTo != null && servedTo.isNotEmpty)
                kv('Served To', servedTo),
              kv('Actual Service Address', headerAddr),
              if (latest != null)
                kv('Latitude', latest.latitude.toStringAsFixed(6)),
              if (latest != null)
                kv('Longitude', latest.longitude.toStringAsFixed(6)),
              if (payRateDollars != null)
                kv('Payment', '\$$payRateDollars'),
              kv('Total Attempts', '$total'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        // ── PREV NOTES FROM SERVICE (chronological running log, oldest first,
        // mirroring the Rockstar email). Skipped when "latest only". ──
        if (!options.latestOnly && attempts.any((a) =>
            (a.photo.note ?? '').trim().isNotEmpty)) ...[
          pw.Text('PREV NOTES FROM SERVICE',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: ink)),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF9FAFB),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // attempts is newest-first; show oldest-first like the email.
                ...attempts.reversed
                    .where((a) => (a.photo.note ?? '').trim().isNotEmpty)
                    .map((a) {
                  final p = a.photo;
                  final stamp = _logStamp(p.takenAt ?? p.timestamp);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.RichText(
                      text: pw.TextSpan(children: [
                        pw.TextSpan(
                          text: '$stamp  -  ',
                          style: pw.TextStyle(
                              fontSize: 9,
                              color: muted,
                              fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(
                          text: (p.note ?? '').trim(),
                          style: const pw.TextStyle(fontSize: 9, color: ink),
                        ),
                      ]),
                    ),
                  );
                }),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
        ],

        pw.Text(options.latestOnly ? 'Latest Attempt' : 'Attempts',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: 6),

        // ── Attempts (newest first, numbered chronologically) ──
        ...selected.map((a) {
          // Chronological attempt number: newest-first list, so #N = total -
          // indexInNewestFirst.
          final idxNewestFirst = attempts.indexOf(a);
          final attemptNo = total - idxNewestFirst;
          final p = a.photo;
          final ts = _friendlyTs(p.takenAt ?? p.timestamp);
          final dist = _distanceLabel(userLat, userLng, p.latitude, p.longitude);
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Attempt #$attemptNo',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: accent)),
                    pw.Text(ts,
                        style: const pw.TextStyle(fontSize: 10, color: ink)),
                  ],
                ),
                pw.SizedBox(height: 6),
                if (options.includeImages && a.imageBytes != null) ...[
                  pw.ClipRRect(
                    horizontalRadius: 6,
                    verticalRadius: 6,
                    child: pw.Image(
                      pw.MemoryImage(a.imageBytes!),
                      width: double.infinity,
                      height: 300,
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                kv('Address', p.address ?? ''),
                kv('Lat / Long',
                    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}'),
                if (dist != null) kv('Distance', dist),
                kv('Notes', p.note ?? ''),
              ],
            ),
          );
        }),
      ],
    ),
  );

  final dir = await getTemporaryDirectory();
  final safeName =
      profileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final file = File('${dir.path}/service-record-$safeName-$dateStr.pdf');
  await file.writeAsBytes(await doc.save());
  return file;
}

String _friendlyTs(String? iso) {
  if (iso == null) return '';
  try {
    return DateFormat('MM/dd/yyyy hh:mm a').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

/// Stamp used in the PREV NOTES log: "08:56 am  -  06/05/2026" (matches the
/// Rockstar email's "time – date" prefix).
String _logStamp(String? iso) {
  if (iso == null) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${DateFormat('hh:mm a').format(dt)}  -  '
        '${DateFormat('MM/dd/yyyy').format(dt)}';
  } catch (_) {
    return iso;
  }
}

String? _distanceLabel(double? uLat, double? uLng, double lat, double lng) {
  if (uLat == null || uLng == null) return null;
  final meters = _haversineMeters(uLat, uLng, lat, lng);
  final feet = meters * 3.28084;
  if (feet < 1000) return '${feet.round()} ft';
  return '${(feet / 5280).toStringAsFixed(2)} mi';
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double d) => d * (math.pi / 180.0);

/// Maps the per-photo category/service value to a human label for the PDF.
String pdfServiceLabel(String? value) => categoryLabel(value);
