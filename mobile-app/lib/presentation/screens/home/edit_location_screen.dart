import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/photo_model.dart';
import '../../providers/photo_provider.dart';

class EditLocationScreen extends ConsumerStatefulWidget {
  const EditLocationScreen({required this.photo, super.key});
  final PhotoModel photo;

  @override
  ConsumerState<EditLocationScreen> createState() => _EditLocationScreenState();
}

class _EditLocationScreenState extends ConsumerState<EditLocationScreen> {
  // Design tokens
  static const _canvas = Color(0xFF0F1219);
  static const _surface = Color(0xFF1C222E);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xFF94A3B8);
  static const _inkSubtle = Color(0xFF6B7A8D);
  static const _separator = Color(0xFF2A3340);
  static const _accent = Color(0xFF4A90E2);
  static const _accentSoft = Color(0x1F4A90E2);
  static const _errorRed = Color(0xFFDC2626);

  late final MapController _mapController;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;

  late double _lat;
  late double _lng;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _lat = widget.photo.latitude;
    _lng = widget.photo.longitude;
    _latCtrl = TextEditingController(text: _lat.toStringAsFixed(6));
    _lngCtrl = TextEditingController(text: _lng.toStringAsFixed(6));
  }

  @override
  void dispose() {
    _mapController.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _lat >= -90 && _lat <= 90 && _lng >= -180 && _lng <= 180;

  void _onMapTap(TapPosition _, LatLng point) {
    HapticFeedback.lightImpact();
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _latCtrl.text = _lat.toStringAsFixed(6);
      _lngCtrl.text = _lng.toStringAsFixed(6);
      _error = null;
    });
    _mapController.move(point, _mapController.camera.zoom);
  }

  void _onLatChanged(String v) {
    final parsed = double.tryParse(v);
    if (parsed != null) {
      setState(() {
        _lat = parsed;
        _error = null;
      });
      if (_valid) {
        _mapController.move(LatLng(_lat, _lng), _mapController.camera.zoom);
      }
    }
  }

  void _onLngChanged(String v) {
    final parsed = double.tryParse(v);
    if (parsed != null) {
      setState(() {
        _lng = parsed;
        _error = null;
      });
      if (_valid) {
        _mapController.move(LatLng(_lat, _lng), _mapController.camera.zoom);
      }
    }
  }

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _error = 'Enter valid coordinates.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(
        updatePhotoLocationProvider((widget.photo.id, _lat, _lng)).future,
      );
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location updated'),
            backgroundColor: const Color(0xFF6B7280),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        context.pop(true); // return true = updated
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: _canvas,
      body: Column(
        children: [
          _buildHeader(),
          // Hint
          Container(
            width: double.infinity,
            color: _accentSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: _accent),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap the map to move the pin, or edit coordinates below',
                    style: TextStyle(
                      fontSize: 12,
                      color: _accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Map
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(_lat, _lng),
                initialZoom: 14,
                minZoom: 2,
                maxZoom: 18,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.photo_tracker',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_lat, _lng),
                      width: 44,
                      height: 56,
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 10,
                            color: _accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bottom panel
          _buildBottomPanel(),
        ],
      ),
    );

  Widget _buildHeader() => Container(
        color: _surface,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                  ),
                  color: _inkMuted,
                  onPressed: context.pop,
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        "Move the pin to update this photo's location",
                        style: TextStyle(fontSize: 12, color: _inkSubtle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildBottomPanel() => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Coordinate inputs
            Row(
              children: [
                Expanded(
                  child: _coordField(
                    label: 'Latitude',
                    controller: _latCtrl,
                    hint: '-90 to 90',
                    onChanged: _onLatChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _coordField(
                    label: 'Longitude',
                    controller: _lngCtrl,
                    hint: '-180 to 180',
                    onChanged: _onLngChanged,
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: _errorRed),
                  const SizedBox(width: 6),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: _errorRed),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: context.pop,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkMuted,
                      side: const BorderSide(color: _separator),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_valid && !_saving) ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _separator,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Save Location',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _coordField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 14,
              color: _ink,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _inkSubtle, fontSize: 13),
              filled: true,
              fillColor: _canvas,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
            ),
          ),
        ],
      );
}
