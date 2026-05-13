import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../data/models/photo_model.dart';
import '../../providers/photo_provider.dart';

class PhotoDetailScreen extends ConsumerStatefulWidget {
  const PhotoDetailScreen({required this.photoId, super.key});

  final int photoId;

  @override
  ConsumerState<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends ConsumerState<PhotoDetailScreen> {
  // ── Design tokens (matches HomeScreenV2) ─────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF5B5BD6);
  static const Color _accentSoft = Color(0xFFEEEEFD);
  static const Color _rushRed = Color(0xFFDC2626);
  static const Color _standardGreen = Color(0xFF059669);
  static const Color _airportBlue = Color(0xFF0284C7);

  bool _imageExpanded = false;

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
        return 'Rush';
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

  PhotoModel? _findPhoto(List<PhotoModel> photos) {
    final matches = photos.where((p) => p.id == widget.photoId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    await Clipboard.setData(ClipboardData(text: mapsUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Maps link copied — paste in your browser',
          ),
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
                  Icons.image_not_supported_outlined,
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
                onPressed: () => context.pop(),
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
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay at bottom
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 100,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Service type badge
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: svcColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _svcIcon(photo.serviceType),
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _svcLabel(photo.serviceType),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Photo ID badge
                    Positioned(
                      bottom: 16,
                      right: 16,
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
                  const SizedBox(height: 16),

                  // Info cards
                  _buildInfoCard(
                    icon: Icons.access_time_rounded,
                    label: 'Captured',
                    value: _formatTs(photo.timestamp),
                    iconColor: _accent,
                  ),
                  const SizedBox(height: 10),

                  // Location card with map action
                  _buildLocationCard(photo),
                  const SizedBox(height: 10),

                  // Note card (if present)
                  if (photo.note != null && photo.note!.isNotEmpty) ...[
                    _buildInfoCard(
                      icon: Icons.notes_rounded,
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

                  // Delete button
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

  // ── Generic info card ─────────────────────────────────────────────────────
  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
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
          ],
        ),
      );

  // ── Location card ─────────────────────────────────────────────────────────
  Widget _buildLocationCard(PhotoModel photo) {
    final hasZip = photo.zipCode != null && photo.zipCode!.isNotEmpty;
    final coordsText = '${photo.latitude.toStringAsFixed(6)}, '
        '${photo.longitude.toStringAsFixed(6)}';

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
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: Color(0xFF059669),
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
                    const SizedBox(height: 3),
                    if (hasZip)
                      Text(
                        'ZIP Code: ${photo.zipCode}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      coordsText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _inkMuted,
                        fontFeatures: [
                          FontFeature.tabularFigures(),
                        ],
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
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.map_rounded,
                  label: 'Open in Maps',
                  color: _accent,
                  onTap: () => _openInMaps(photo.latitude, photo.longitude),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.copy_rounded,
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
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: dark ? _ink : Colors.white,
          ),
        ),
      );
}
