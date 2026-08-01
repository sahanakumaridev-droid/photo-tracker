import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';

import 'attempt_draft_controller.dart';
import 'location_picker_map.dart';

/// Dedicated Location screen, pushed from the Resume Attempt hub. Body is
/// the old form's location section — Refresh/Pick-on-Map/error/shimmer
/// sub-states and the `locationFrozenFromCache` guard — rebound to the
/// shared [AttemptDraftController].
class AttemptLocationScreen extends ConsumerWidget {
  const AttemptLocationScreen({super.key, required this.controller});

  final AttemptDraftController controller;

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF7F5FF);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _inkMuted = Color(0xFF6B7280);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEDE9FE);
  static const Color _errorRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 22, color: _inkMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'GPS / Location',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _buildLocationSection(context, ref),
          ),
        ),
      ),
    );
  }

  Future<void> _openMapPicker(BuildContext context, WidgetRef ref) async {
    final initial = (controller.latitude != null && controller.longitude != null)
        ? LatLng(controller.latitude!, controller.longitude!)
        : null;

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerMap(initial: initial),
      ),
    );

    if (picked == null || !context.mounted) return;
    await controller.applyPickedLocation(picked, context, ref);
  }

  // ── Location section ──────────────────────────────────────────────────────
  Widget _buildLocationSection(BuildContext context, WidgetRef ref) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionLabel(
                    'Location',
                    Icons.location_on_rounded,
                    required: true,
                    done: controller.latitude != null &&
                        !controller.isLoadingLocation,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _openMapPicker(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 13, color: _accent),
                        SizedBox(width: 4),
                        Text(
                          'Pick on Map',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (controller.locationFrozenFromCache) {
                      controller.showSnack(
                        context,
                        'Location is locked from cache. Unlock from the hub banner to refresh GPS.',
                      );
                      return;
                    }
                    controller.fetchLocation(context, ref);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _canvas,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: controller.isLoadingLocation
                              ? _inkSubtle
                              : _accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          controller.isLoadingLocation
                              ? 'Locating…'
                              : 'Refresh',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: controller.isLoadingLocation
                                ? _inkSubtle
                                : _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Loading (shimmer) ────────────────────────────────────
            if (controller.isLoadingLocation)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent),
                      ),
                      SizedBox(width: 10),
                      Text('Fetching current location…',
                          style: TextStyle(fontSize: 13, color: _inkMuted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _shimmerBox(height: 48, radius: 12),
                  const SizedBox(height: 8),
                  _shimmerBox(height: 44, radius: 12),
                  const SizedBox(height: 8),
                  _shimmerBox(height: 40, radius: 12),
                ],
              )

            // ── Error ────────────────────────────────────────────────
            else if (controller.locationError || controller.latitude == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_off_outlined,
                      size: 18,
                      color: _errorRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.locationErrorMsg ??
                            'Location unavailable. Tap Refresh to retry.',
                        style: const TextStyle(fontSize: 13, color: _errorRed),
                      ),
                    ),
                  ],
                ),
              )

            // ── Success ──────────────────────────────────────────────
            else ...[
              _fieldLabel('Address', optional: false),
              const SizedBox(height: 6),
              Stack(
                children: [
                  TextField(
                    controller: controller.addressController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _ink,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Street, City, State, ZIP',
                      hintStyle: const TextStyle(
                        color: _inkSubtle,
                        fontSize: 13,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 18,
                          color: _inkSubtle,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      filled: true,
                      fillColor: _canvas,
                      contentPadding: const EdgeInsets.fromLTRB(
                        0,
                        12,
                        44,
                        12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: controller.toggleEditingAddress,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          controller.isEditingAddress
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                          size: 14,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Lat / Lon (read-only) ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: (controller.gpsAccuracy != null &&
                              controller.gpsAccuracy! > 50)
                          ? Colors.orange
                          : _inkSubtle,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${controller.latitude!.toStringAsFixed(6)},  '
                            '${controller.longitude!.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _inkMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (controller.gpsAccuracy != null)
                            Text(
                              'Accuracy: ±${controller.gpsAccuracy!.toStringAsFixed(0)}m'
                              '${controller.gpsAccuracy! > 50 ? ' (low — tap Refresh)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: controller.gpsAccuracy! > 50
                                    ? Colors.orange
                                    : _inkSubtle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(
    String label,
    IconData icon, {
    bool required = false,
    bool done = false,
  }) =>
      Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: done
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
                    ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: done
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Icon(
              done ? Icons.check_rounded : icon,
              size: 16,
              color: done ? Colors.white : _accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
              letterSpacing: -0.2,
            ),
          ),
          if (required && !done) ...[
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                fontSize: 14,
                color: _errorRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (done) ...[
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _fieldLabel(String label, {bool optional = false}) => Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _inkMuted,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: _canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'optional',
                style: TextStyle(
                  fontSize: 10,
                  color: _inkSubtle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      );

  /// Shimmer placeholder — used while loading location.
  Widget _shimmerBox({required double height, double radius = 8}) =>
      Shimmer.fromColors(
        baseColor: const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}
