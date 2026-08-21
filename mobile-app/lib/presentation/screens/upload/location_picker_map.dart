import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/location_service.dart';
import '../../widgets/ai/voice_mic_button.dart';

/// Result returned by [LocationPickerMap]: the chosen point plus the address
/// the picker resolved for it (so the caller shows exactly what was confirmed).
class PickedLocation {
  const PickedLocation(this.latLng, this.address);
  final LatLng latLng;
  final String? address;
}

/// Full-screen map picker with location search.
///
/// Returns a [PickedLocation] via [Navigator.pop] when the user confirms.
/// If [initial] is null, the map opens at the device's real GPS location.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({super.key, this.initial});

  final LatLng? initial;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _surface = Color(0xFFFFFFFF);

  late MapController _mapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  LatLng? _pinPosition;
  bool _isDragging = false;
  bool _locating = false;
  bool _loadingInitial = false;
  bool _searching = false;
  String? _resolvedAddress;

  List<_SearchResult> _searchResults = [];
  bool _showResults = false;
  Timer? _debounce;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController.addListener(_onSearchChanged);

    if (widget.initial != null) {
      _pinPosition = widget.initial;
      _fetchAddressForPosition(widget.initial!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(widget.initial!, 15);
      });
    } else {
      _fetchInitialLocation();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    _debounce?.cancel();
    _dio.close();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _searchLocation(_searchController.text);
    });
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().length < 2) {
      setState(() { _searchResults = []; _showResults = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': 5,
          'addressdetails': 1,
          'accept-language': 'en',
        },
        options: Options(headers: {'User-Agent': 'GeoTag/1.0'}),
      );
      final results = (response.data as List)
          .map((j) => _SearchResult(
                displayName: j['display_name'] as String,
                lat: double.parse(j['lat'] as String),
                lon: double.parse(j['lon'] as String),
              ))
          .toList();
      if (mounted) setState(() { _searchResults = results; _showResults = results.isNotEmpty; });
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _selectSearchResult(_SearchResult r) async {
    setState(() {
      _showResults = false;
      _searchResults = [];
      _searchController.text = r.displayName;
      _pinPosition = LatLng(r.lat, r.lon);
      _searchFocus.unfocus();
    });
    _mapController.move(LatLng(r.lat, r.lon), 17);
    await _fetchAddressForPosition(LatLng(r.lat, r.lon));
  }

  Future<void> _fetchAddressForPosition(LatLng pos) async {
    try {
      final addr = await LocationService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _resolvedAddress = addr);
      }
    } catch (_) {}
  }

  Future<void> _fetchInitialLocation() async {
    setState(() => _loadingInitial = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (!mounted) return;
      if (pos != null) {
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _loadingInitial = false;
          _pinPosition = ll;
        });
        _fetchAddressForPosition(ll);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(ll, 15);
        });
        return;
      }
    } catch (_) {}
    // GPS truly failed — let user search or tap map. Start at a neutral world view.
    if (!mounted) return;
    setState(() {
      _loadingInitial = false;
      _pinPosition = const LatLng(0, 0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(const LatLng(0, 0), 2);
    });
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null || !mounted) {
        setState(() => _locating = false);
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      _mapController.move(ll, 17);
      setState(() {
        _pinPosition = ll;
        _locating = false;
      });
      _fetchAddressForPosition(ll);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    // The centre pin is the selection — read the live map centre so the
    // confirmed point always matches exactly what the user sees under the pin.
    LatLng picked;
    try {
      picked = _mapController.camera.center;
    } catch (_) {
      picked = _pinPosition ?? const LatLng(0, 0);
    }
    if (picked.latitude == 0 && picked.longitude == 0) {
      picked = _pinPosition ?? picked;
    }
    if (picked.latitude == 0 && picked.longitude == 0) return;
    Navigator.of(context).pop(PickedLocation(picked, _resolvedAddress));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitial || _pinPosition == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F4F7),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: _accent),
            const SizedBox(height: 16),
            Text('Getting your location…', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: Stack(children: [
        // ── Map ──────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _pinPosition!,
            initialZoom: 15,
            minZoom: 2,
            maxZoom: 18,
            onTap: (_, latLng) {
              // Recenter the map on the tapped point so the centre pin (the
              // source of truth on confirm) sits exactly where the user tapped.
              _mapController.move(latLng, _mapController.camera.zoom);
              setState(() {
                _pinPosition = latLng;
                _showResults = false;
                _searchFocus.unfocus();
              });
              _fetchAddressForPosition(latLng);
            },
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
                // Keep the pin + resolved address in sync with the final centre
                // so Confirm returns exactly what's shown under the pin.
                final c = _mapController.camera.center;
                _pinPosition = c;
                _fetchAddressForPosition(c);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: false,
              tileSize: 256,
              userAgentPackageName: 'com.example.photo_tracker',
            ),
          ],
        ),

        // ── Centre pin ───────────────────────────────────────────────
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, _isDragging ? -20 : -24, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _accent, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: _isDragging ? 16 : 8, spreadRadius: _isDragging ? 4 : 2),
                  ],
                ),
                child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
              ),
              Container(width: 3, height: 12, color: _accent),
              Container(width: _isDragging ? 10 : 6, height: _isDragging ? 4 : 3,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4))),
            ]),
          ),
        ),

        // ── Search bar ───────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16, right: 16,
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 14, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Say an address or place…',
                  hintStyle: const TextStyle(fontSize: 14, color: _inkSubtle),
                  prefixIcon: _searching
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)))
                      : const Icon(Icons.search_rounded, color: _inkSubtle, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VoiceMicButton(controller: _searchController),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: _inkSubtle,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _showResults = false);
                          },
                        ),
                    ],
                  ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),

            // ── Search results dropdown ─────────────────────────────
            if (_showResults && _searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: _searchResults.map((r) => InkWell(
                    onTap: () => _selectSearchResult(r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: _accent),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r.displayName, style: const TextStyle(fontSize: 13, color: _ink), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
          ]),
        ),

        // ── Address chip ─────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 120,
          left: 24, right: 24,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Text(
                _resolvedAddress ?? '${_pinPosition!.latitude.toStringAsFixed(6)}, ${_pinPosition!.longitude.toStringAsFixed(6)}',
                style: TextStyle(fontSize: 11, color: _resolvedAddress != null ? _inkMuted : _inkSubtle, fontFamily: _resolvedAddress != null ? null : 'monospace'),
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),

        // ── My Location + Confirm buttons ────────────────────────────
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 24, right: 24,
          child: Row(children: [
            FloatingActionButton.small(
              heroTag: 'my_loc',
              onPressed: _locating ? null : _goToMyLocation,
              backgroundColor: _surface,
              foregroundColor: _accent,
              elevation: 4,
              child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.location_on_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirm Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SearchResult {
  final String displayName;
  final double lat;
  final double lon;
  const _SearchResult({required this.displayName, required this.lat, required this.lon});
}
