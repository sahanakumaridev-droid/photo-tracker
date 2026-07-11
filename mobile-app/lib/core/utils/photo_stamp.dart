import 'dart:io';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Photo timestamp + watermark helpers.
///
/// The timestamp always comes from the photo itself (EXIF capture time),
/// never from a user action. The same caption is used for the live preview
/// ([WatermarkBar]) and the baked-in upload ([applyWatermark]) so the two can
/// never drift apart.

/// Reads the photo's real capture time from EXIF (DateTimeOriginal) so the
/// stamp reflects when the picture was TAKEN (from the gallery photo's
/// metadata). Falls back to the file's last-modified time when there is no
/// EXIF date, and to "now" only if reading fails entirely.
Future<String> readCaptureTimeIso(File f) async {
  try {
    final tags = await readExifFromBytes(await f.readAsBytes());
    final tag = tags['EXIF DateTimeOriginal'] ??
        tags['EXIF DateTimeDigitized'] ??
        tags['Image DateTime'];
    if (tag != null) {
      final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})')
          .firstMatch(tag.printable);
      if (m != null) {
        final local = DateTime(
          int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
          int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!),
        );
        debugPrint('[photo_stamp] EXIF capture time: ${tag.printable}');
        return local.toUtc().toIso8601String();
      }
    }
    // No EXIF date (e.g. a screenshot, or the picker stripped metadata).
    // Use the file's last-modified time — closer to the real date than now.
    final modified = f.lastModifiedSync();
    debugPrint('[photo_stamp] no EXIF date; using file mtime: $modified');
    return modified.toUtc().toIso8601String();
  } catch (e) {
    debugPrint('[photo_stamp] capture-time read failed: $e');
    return DateTime.now().toUtc().toIso8601String();
  }
}

/// Builds the full watermark caption: "yyyy-MM-dd HH:mm:ss  •  <address>".
String buildWatermarkText(String takenAtIso, String address) {
  final ts = formatStamp(takenAtIso);
  final parts = <String>[
    ts,
    if (address.trim().isNotEmpty) address.trim(),
  ];
  return parts.join('  •  ');
}

/// Friendly timestamp for the overlay, e.g. "06/22/2026 08:28 AM".
String formatStampFriendly(String? iso) {
  if (iso == null) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('MM/dd/yyyy hh:mm a').format(dt);
  } catch (_) {
    return iso;
  }
}

/// Builds the multi-line overlay caption the client requires baked into every
/// photo:
///   06/22/2026 08:28 AM
///   4822 Reno Drive
///   32.690861, -117.113289
///   Standard · Attempt #3 · Agent: Donald
/// Empty fields are dropped so the bar only shows what's known.
List<String> buildStampLines({
  required String takenAtIso,
  String address = '',
  double? latitude,
  double? longitude,
  String? serviceLabel,
  int? attemptNumber,
  String? agentName,
}) {
  final lines = <String>[];
  final ts = formatStampFriendly(takenAtIso);
  if (ts.isNotEmpty) lines.add(ts);
  if (address.trim().isNotEmpty) lines.add(address.trim());
  if (latitude != null && longitude != null) {
    lines.add('${latitude.toStringAsFixed(6)}, '
        '${longitude.toStringAsFixed(6)}');
  }
  final meta = <String>[
    if (serviceLabel != null && serviceLabel.trim().isNotEmpty)
      serviceLabel.trim(),
    if (attemptNumber != null) 'Attempt #$attemptNumber',
    if (agentName != null && agentName.trim().isNotEmpty)
      'Agent: ${agentName.trim()}',
  ];
  if (meta.isNotEmpty) lines.add(meta.join('  ·  '));
  return lines;
}

/// Full timestamp label, e.g. "2026-06-18 14:05:33".
String formatStamp(String? iso) {
  if (iso == null) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  } catch (_) {
    return iso;
  }
}

/// Compact timestamp label for thumbnails, e.g. "06/18 14:05".
String shortStamp(String? iso) {
  if (iso == null) return '…';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('MM/dd HH:mm').format(dt);
  } catch (_) {
    return iso;
  }
}

/// Bakes the watermark caption into the bottom of [imageFile] and returns a
/// new temp PNG. Returns the original file unchanged if anything fails.
///
/// The overlay is a semi-transparent black bar with white text. When the
/// richer fields (lat/long, service, attempt #, agent) are supplied it renders
/// the multi-line client-required caption; otherwise it falls back to the
/// classic "timestamp • address" single line.
///
/// Decoding goes through Flutter's platform image codec ([ui.ImageDescriptor]),
/// so it handles every format the phone camera produces — including HEIC, which
/// the pure-Dart `image` decoder cannot read. (A HEIC camera shot was the
/// reason real-device uploads came back un-watermarked.) The caption pixels are
/// then drawn with the `image` package (CPU) instead of Flutter's GPU canvas,
/// because the old `Picture.toImage()` path rendered the text as blank under
/// Impeller in release builds. The CPU draw runs in a background isolate via
/// [compute] so large photos don't jank the UI.
Future<File> applyWatermark(
  File imageFile,
  String takenAtIso,
  String address, {
  double? latitude,
  double? longitude,
  String? serviceLabel,
  int? attemptNumber,
  String? agentName,
}) async {
  try {
    final bytes = await imageFile.readAsBytes();

    // Decode + downscale with the platform codec. This is plain decoding (NOT
    // the Canvas/Picture text path Impeller renders blank) and it bakes in EXIF
    // orientation, so portrait shots come out upright.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    const maxW = 1920;
    final ow = descriptor.width;
    final oh = descriptor.height;
    final scale = ow > maxW ? maxW / ow : 1.0;
    final tw = (ow * scale).round();
    final th = (oh * scale).round();
    final codec =
        await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;
    final rgba =
        await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = uiImage.width;
    final h = uiImage.height;
    uiImage.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (rgba == null) {
      debugPrint('[photo_stamp] could not read pixels, using original');
      return imageFile;
    }

    var lines = buildStampLines(
      takenAtIso: takenAtIso,
      address: address,
      latitude: latitude,
      longitude: longitude,
      serviceLabel: serviceLabel,
      attemptNumber: attemptNumber,
      agentName: agentName,
    );
    if (lines.isEmpty) lines = [buildWatermarkText(takenAtIso, address)];

    final png = await compute(
      _bakeWatermark,
      _BakeRequest(rgba.buffer.asUint8List(), w, h, lines),
    );
    if (png == null) {
      debugPrint('[photo_stamp] watermark draw failed, using original');
      return imageFile;
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = File('${dir.path}/wm_$stamp.png');
    await out.writeAsBytes(png);
    debugPrint('[photo_stamp] watermark baked → ${out.path} (${w}x$h)');
    return out;
  } catch (e) {
    debugPrint('[photo_stamp] watermark failed, using original: $e');
    return imageFile; // fall back to original if watermark fails
  }
}

/// Isolate payload for [_bakeWatermark] — raw RGBA pixels (already decoded and
/// downscaled), the image dimensions, and the caption lines.
class _BakeRequest {
  const _BakeRequest(this.rgba, this.width, this.height, this.lines);
  final Uint8List rgba;
  final int width;
  final int height;
  final List<String> lines;
}

/// Runs on a background isolate (via [compute]). Wraps the decoded RGBA pixels,
/// draws the caption bar + centred text with a bitmap font, and returns PNG
/// bytes. Returns null only if the buffer can't be wrapped as an image.
Uint8List? _bakeWatermark(_BakeRequest req) {
  // Strip the decoded RGBA to 3-channel RGB. fillRect/drawString blend a
  // semi-transparent colour correctly onto an opaque (no-alpha) image; on a
  // 4-channel image the same blend zeroes the alpha, making the bar and text
  // fully transparent (invisible over the photo). RGB sidesteps that entirely.
  final src = req.rgba;
  final px = req.width * req.height;
  final rgb = Uint8List(px * 3);
  for (var i = 0; i < px; i++) {
    rgb[i * 3] = src[i * 4];
    rgb[i * 3 + 1] = src[i * 4 + 1];
    rgb[i * 3 + 2] = src[i * 4 + 2];
  }
  final out = img.Image.fromBytes(
    width: req.width,
    height: req.height,
    bytes: rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final w = out.width;
  final h = out.height;

  // Pick a bitmap font that stays readable relative to the output width.
  final font = w >= 900 ? img.arial48 : img.arial24;
  final lineH = font.lineHeight;
  final padY = (lineH * 0.5).round();

  final barH = lineH * req.lines.length + padY * 2;
  final barTop = (h - barH).clamp(0, h);

  // Semi-transparent black bar across the bottom for contrast.
  img.fillRect(
    out,
    x1: 0,
    y1: barTop,
    x2: w - 1,
    y2: h - 1,
    color: img.ColorRgba8(0, 0, 0, 150),
  );

  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  var y = barTop + padY;
  for (final raw in req.lines) {
    // Bitmap arial covers Latin-1; swap the bullet/middot separators (which it
    // lacks) for an ASCII dash so meta lines don't lose their separators.
    final line = raw.replaceAll('•', '-').replaceAll('·', '-');
    final tw = _measureLine(font, line);
    final x = ((w - tw) / 2).round().clamp(0, w);
    // 2px black shadow under the white text keeps it legible on bright photos.
    img.drawString(out, line, font: font, x: x + 2, y: y + 2, color: black);
    img.drawString(out, line, font: font, x: x, y: y, color: white);
    y += lineH;
  }

  return img.encodePng(out);
}

/// Pixel width of [s] in [font], summing each glyph's advance.
int _measureLine(img.BitmapFont font, String s) {
  var width = 0;
  for (final c in s.codeUnits) {
    final ch = font.characters[c];
    if (ch != null) width += ch.xAdvance;
  }
  return width;
}

/// A live, non-destructive preview of the watermark caption — drawn as a
/// Flutter overlay so the user sees exactly what gets baked at upload.
class WatermarkBar extends StatelessWidget {
  const WatermarkBar({
    required this.takenAtIso,
    this.address = '',
    this.compact = false,
    super.key,
  });

  /// ISO-8601 capture time; null while EXIF is still being read.
  final String? takenAtIso;
  final String address;

  /// Compact mode = small chip for thumbnails; full = wide caption bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = takenAtIso == null
        ? 'Reading time…'
        : compact
            ? shortStamp(takenAtIso)
            : buildWatermarkText(takenAtIso!, address);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 14,
        vertical: compact ? 3 : 9,
      ),
      color: Colors.black.withValues(alpha: 0.45),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: compact ? 10 : 14,
            color: Colors.white,
          ),
          SizedBox(width: compact ? 3 : 6),
          Flexible(
            child: Text(
              text,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 9 : 13,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full multi-line watermark caption, drawn as a display overlay across the
/// bottom of a photo (date / address / coordinates / service · attempt · agent).
///
/// This renders from the post's metadata at display time, so EVERY post shows
/// the caption — including older photos uploaded before the watermark was baked
/// in. Drop it as the last child of a [Stack] sized to the image. Renders
/// nothing when there's no data to show.
class WatermarkCaption extends StatelessWidget {
  const WatermarkCaption({
    required this.takenAtIso,
    this.address = '',
    this.latitude,
    this.longitude,
    this.serviceLabel,
    this.attemptNumber,
    this.agentName,
    this.compact = false,
    super.key,
  });

  final String? takenAtIso;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? serviceLabel;
  final int? attemptNumber;
  final String? agentName;

  /// Compact = smaller text for feed cards; full = larger for the detail view.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lines = buildStampLines(
      takenAtIso: takenAtIso ?? '',
      address: address,
      latitude: latitude,
      longitude: longitude,
      serviceLabel: serviceLabel,
      attemptNumber: attemptNumber,
      agentName: agentName,
    );
    if (lines.isEmpty) return const SizedBox.shrink();

    final double fontSize = compact ? 12 : 14;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          padding: EdgeInsets.fromLTRB(
              14, compact ? 22 : 30, 14, compact ? 10 : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.66),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Text(
                  line,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 5),
                      Shadow(color: Colors.black, blurRadius: 10),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
