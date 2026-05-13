import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/location_service.dart';

/// Full-screen map picker.
///
/// Returns the picked [LatLng] via [Navigator.pop] when the user confirms.
/// If [initial] is null, the map opens at the device's real GPS location.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({super.key, this.initial});

  final LatLng? initial;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  static const Color _accent = Color(0xFF5B5BD6);

  late MapController _mapController;

  /// Null while we're still fetching the initial GPS fix.
  LatLng? _pinPosition;

  bool _isDragging = false;
  bool _locating = false;
  bool _loadingInitial = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    if (widget.initial != null) {
      // Caller already has a GPS fix — use it directly.
      _pinPosition = widget.initial;
    } else {
      // No fix passed in → fetch the real device location.
      _fetchInitialLocation();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ── Fetch real device GPS on open ─────────────────────────────────────────
  Future<void> _fetchInitialLocation() async {
    setState(() => _loadingInitial = true);
    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    final ll = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(0, 0); // absolute last resort if GPS denied
    setState(() {
      _loadingInitial = false;
      _pinPosition = ll;
    });
    // Move map after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(ll, 15);
    });
  }

  // ── My Location button ────────────────────────────────────────────────────
  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    final pos = await LocationService.getCurrentLocation();
    setState(() => _locating = false);
    if (pos == null || !mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    _mapController.move(ll, 16);
    setState(() => _pinPosition = ll);
  }

  // ── Confirm ───────────────────────────────────────────────────────────────
  void _confirm() {
    if (_pinPosition != null) Navigator.of(context).pop(_pinPosition);
  }

  @override
  Widget build(BuildContext context) {
    // Show spinner while fetching initial GPS
    if (_loadingInitial || _pinPosition == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _accent),
              const SizedBox(height: 16),
              Text(
                'Getting your location…',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pin = _pinPosition!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: pin,
              initialZoom: 15,
              minZoom: 2,
              maxZoom: 18,
              // Tap anywhere → snap pin there
              onTap: (_, latLng) => setState(() => _pinPosition = latLng),
              // Drag map → pin follows centre
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  setState(() {
                    _pinPosition = position.center;
                    _isDragging = true;
                  });
                }
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd ||
                    event is MapEventFlingAnimationEnd ||
                    event is MapEventDoubleTapZoomEnd) {
                  setState(() => _isDragging = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.photo_tracker',
              ),
            ],
          ),

          // ── Centre pin ───────────────────────────────────────────────
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(
                0,
                _isDragging ? -20 : -24,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.45),
                          blurRadius: _isDragging ? 16 : 8,
                          spreadRadius: _isDragging ? 4 : 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  Container(width: 3, height: 12, color: _accent),
                  Container(
                    width: _isDragging ? 10 : 6,
                    height: _isDragging ? 4 : 3,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Coordinate chip ──────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${pin.latitude.toStringAsFixed(6)},  '
                  '${pin.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF0D1117),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // ── App bar ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF4B5563),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Pick Location',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D1117),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'Drag or tap to place pin',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── My Location FAB ──────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 110,
            child: FloatingActionButton.small(
              heroTag: 'picker_my_location',
              onPressed: _locating ? null : _goToMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: _accent,
              elevation: 4,
              tooltip: 'My location',
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          // ── Confirm button ───────────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'Confirm Location',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
