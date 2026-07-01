import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../data/models/photo_model.dart';

/// Full-screen, swipeable, zoomable image preview for a set of photos.
///
/// Open with [PhotoPreviewGallery.open] — typically from a thumbnail grid so
/// the user can quickly flick through every photo at a location without
/// leaving for the full detail screen.
class PhotoPreviewGallery extends StatefulWidget {
  const PhotoPreviewGallery({
    required this.photos,
    this.initialIndex = 0,
    super.key,
  });

  final List<PhotoModel> photos;
  final int initialIndex;

  /// Push the gallery as an opaque full-screen route.
  static Future<void> open(
    BuildContext context, {
    required List<PhotoModel> photos,
    int initialIndex = 0,
  }) {
    HapticFeedback.lightImpact();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        fullscreenDialog: true,
        pageBuilder: (_, __, ___) => PhotoPreviewGallery(
          photos: photos,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<PhotoPreviewGallery> createState() => _PhotoPreviewGalleryState();
}

class _PhotoPreviewGalleryState extends State<PhotoPreviewGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  String _caption(PhotoModel p) {
    final parts = <String>[];
    if (p.address != null && p.address!.trim().isNotEmpty) {
      parts.add(p.address!.trim());
    } else if (p.zipCode != null && p.zipCode!.isNotEmpty) {
      parts.add('ZIP ${p.zipCode}');
    }
    if (p.timestamp != null) {
      try {
        parts.add(DateFormat('MMM d, yyyy • h:mm a')
            .format(DateTime.parse(p.timestamp!).toLocal()));
      } catch (_) {}
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final current = photos[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable, zoomable pages
          PageView.builder(
            controller: _controller,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: _fullUrl(photos[i].imageUrl),
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(CupertinoIcons.photo,
                          size: 48, color: Colors.white38),
                    ),
                  ),
                ),
              );
            },
          ),

          // Top bar: close + counter
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark,
                        color: Colors.white, size: 24),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                  if (photos.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} / ${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom caption
          if (_caption(current).isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  _caption(current),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
