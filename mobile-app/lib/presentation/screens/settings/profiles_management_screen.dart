import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/map_tiles.dart';
import '../../../core/ai/spoken_parser.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/profile_lifecycle.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/delivery_style.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/speak_fill_banner.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../upload/location_picker_map.dart';

class ProfilesManagementScreen extends ConsumerStatefulWidget {
  const ProfilesManagementScreen({
    super.key,
    this.profileToEdit,
  });
  final ProfileModel? profileToEdit;

  @override
  ConsumerState<ProfilesManagementScreen> createState() =>
      _ProfilesManagementScreenState();
}

class _ProfilesManagementScreenState
    extends ConsumerState<ProfilesManagementScreen> {
  // ── Design tokens — matches the rest of the app (Upload screen, Profile
  // Detail): soft-lavender canvas, white cards with a subtle shadow, colored
  // icon badges per section. ─────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _separator = Color(0xFFE3E7EE);
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorRed = Color(0xFFEF4444);
  static const LinearGradient _btnGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF64B5F6), Color(0xFF4A90E2)],
  );

  late TextEditingController _nameController;
  late TextEditingController _noteController;
  late TextEditingController _payRateController;
  String _selectedServiceType = 'standard';
  late String _companyId;
  String? _deliveryStyle;
  bool _isLoading = false;

  // ── Status: independent of any Attempt/Photo status. ──────────────────────
  String? _status;

  // ── Profile Location: independent of any Attempt's captured GPS. Settable
  // before any photo/attempt exists — see LocationPickerMap for the map +
  // address-search picker this reuses (same one the Upload flow uses for
  // Attempt location, kept structurally separate here). ──────────────────────
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  bool _locatingCurrent = false;
  bool _coordsExpanded = false;

  /// Stepper: Basics → Company → Location.
  int _step = 0;
  static const int _stepCount = 3;
  static const List<String> _stepTitles = [
    'Basics',
    'Company',
    'Location',
  ];
  static const List<String> _stepSubtitles = [
    'Name and status for this profile.',
    'Company, priority, delivery style, and payout.',
    'Optional work location for this profile.',
  ];

  bool get _isEditing => widget.profileToEdit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.profileToEdit;
    _nameController = TextEditingController(text: p?.name ?? '');
    _noteController = TextEditingController(text: p?.note ?? '');
    _payRateController =
        TextEditingController(text: p?.payRate?.toString() ?? '');
    _companyId = companyById(p?.company)?.id ?? kDefaultCompanyId;
    final savedStyle = (p?.deliveryStyle ?? '').trim();
    _deliveryStyle =
        kDeliveryStyles.contains(savedStyle) ? savedStyle : null;
    if (p?.serviceType != null &&
        companyOrDefault(_companyId).allowsPriority(p!.serviceType)) {
      _selectedServiceType = p.serviceType;
    } else {
      _selectedServiceType = defaultPriorityForCompany(_companyId);
    }
    _status = p?.status;
    _addressController = TextEditingController(text: p?.address ?? '');
    _cityController = TextEditingController(text: p?.city ?? '');
    _stateController = TextEditingController(text: p?.state ?? '');
    _zipController = TextEditingController(text: p?.postalCode ?? '');
    _latController =
        TextEditingController(text: p?.latitude?.toStringAsFixed(6) ?? '');
    _lngController =
        TextEditingController(text: p?.longitude?.toStringAsFixed(6) ?? '');
    // Map legacy values (rush→asap, airport→standard) to the 4 categories
    final raw = widget.profileToEdit?.serviceType ?? 'standard';
    const valid = {'asap', 'standard', 'special', 'next_day'};
    _selectedServiceType = valid.contains(raw)
        ? raw
        : (raw == 'rush' ? 'asap' : 'standard');
    // Profile Name is required — its "done" badge must update live as the
    // user types, matching the Upload screen's required-field pattern.
    _nameController.addListener(_onNameChanged);
    _payRateController.addListener(_onNameChanged);

    // Convenience auto-fill: whenever there's no Profile Location yet — a
    // brand-new profile, or an existing one nobody has set a location for —
    // pre-fill the device's current location (silently; failure just leaves
    // the fields blank, it never blocks saving). A profile that already HAS
    // a saved location is never touched: `_hasLocation` guards against
    // overwriting real data with wherever the device happens to be right now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasLocation) _useCurrentLocation();
    });
  }

  void _onNameChanged() => setState(() {});

  void _applyDraft(SpokenDraft d) {
    setState(() {
      if (d.name != null && d.name!.trim().isNotEmpty) {
        _nameController.text = d.name!;
      }
      if (d.companyId != null) {
        _companyId = d.companyId!;
        if (!companyOrDefault(_companyId).allowsPriority(_selectedServiceType)) {
          _selectedServiceType = defaultPriorityForCompany(_companyId);
        }
      }
      if (d.priority != null &&
          companyOrDefault(_companyId).allowsPriority(d.priority)) {
        _selectedServiceType = d.priority!;
      }
      if (d.payRate != null) {
        _payRateController.text = '${d.payRate}';
      }
      if (d.address != null) _addressController.text = d.address!;
      if (d.city != null) _cityController.text = d.city!;
      if (d.state != null) _stateController.text = d.state!;
      if (d.postalCode != null) _zipController.text = d.postalCode!;
      if (d.note != null) _noteController.text = d.note!;
    });
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    _payRateController
      ..removeListener(_onNameChanged)
      ..dispose();
    _noteController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  bool get _hasLocation =>
      _latController.text.trim().isNotEmpty &&
      _lngController.text.trim().isNotEmpty;

  LatLng? get _previewPoint {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String get _locationSummary {
    final parts = <String>[
      if (_addressController.text.trim().isNotEmpty)
        _addressController.text.trim(),
      if (_cityController.text.trim().isNotEmpty) _cityController.text.trim(),
      if (_stateController.text.trim().isNotEmpty) _stateController.text.trim(),
      if (_zipController.text.trim().isNotEmpty) _zipController.text.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    if (_hasLocation) {
      return '${_latController.text.trim()}, ${_lngController.text.trim()}';
    }
    return '';
  }

  String get _statusHelper {
    switch (normalizeProfileStatus(_status)) {
      case kProfileInProgress:
        return 'At least one attempt is logged. Diligence is not met yet.';
      case kProfileCompleted:
        return 'Successful attempt or diligence is complete. Archive after payment.';
      case kProfileArchived:
        return 'Paid in full. Export only.';
      default:
        return 'Created, but no attempt has been made yet.';
    }
  }

  void _applyPickedLocation(
    double lat,
    double lng, {
    String? fallbackAddress,
  }) {
    setState(() {
      _latController.text = lat.toStringAsFixed(6);
      _lngController.text = lng.toStringAsFixed(6);
      if (fallbackAddress != null) _addressController.text = fallbackAddress;
    });
    // Best-effort: fill discrete Address/City/State/ZIP fields. Runs after
    // the lat/lng are already shown so the picker never feels stuck waiting
    // on the network.
    LocationService.reverseGeocodeDetailed(lat, lng).then((c) {
      if (!mounted) return;
      setState(() {
        if (c.street != null) _addressController.text = c.street!;
        if (c.city != null) _cityController.text = c.city!;
        if (c.state != null) _stateController.text = c.state!;
        if (c.zip != null) _zipController.text = c.zip!;
      });
    });
  }

  Future<void> _pickOnMap() async {
    final initial = _hasLocation
        ? LatLng(
            double.tryParse(_latController.text) ?? 0,
            double.tryParse(_lngController.text) ?? 0,
          )
        : null;
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerMap(initial: initial),
      ),
    );
    if (picked == null || !mounted) return;
    _applyPickedLocation(
      picked.latLng.latitude,
      picked.latLng.longitude,
      fallbackAddress: picked.address,
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingCurrent = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null || !mounted) return;
      _applyPickedLocation(pos.latitude, pos.longitude);
    } finally {
      if (mounted) setState(() => _locatingCurrent = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _addressController.clear();
      _cityController.clear();
      _stateController.clear();
      _zipController.clear();
      _latController.clear();
      _lngController.clear();
      _coordsExpanded = false;
    });
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name')),
      );
      return;
    }
    if (_deliveryStyle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a delivery style')),
      );
      return;
    }
    final payRate = int.tryParse(_payRateController.text.trim());
    if (payRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a payout amount')),
      );
      return;
    }
    // Only treated as set when BOTH parse — a partially-edited pair is
    // treated as "not set" rather than silently saving a mismatched point.
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final hasCoords = lat != null && lng != null;

    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    setState(() => _isLoading = true);
    try {
      if (widget.profileToEdit != null) {
        // Update existing profile
        await ref.read(updateProfileProvider((
          profileId: widget.profileToEdit!.id,
          name: _nameController.text.trim(),
          serviceType: _selectedServiceType,
          company: _companyId,
          note: _noteController.text.isEmpty ? null : _noteController.text,
          payRate: payRate,
          deliveryStyle: _deliveryStyle,
          status: null,
          address: orNull(_addressController),
          city: orNull(_cityController),
          state: orNull(_stateController),
          postalCode: orNull(_zipController),
          latitude: hasCoords ? lat : null,
          longitude: hasCoords ? lng : null,
        )).future);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
        }
      } else {
        // Create new profile
        final created = await ref.read(createProfileProvider((
          name: _nameController.text.trim(),
          serviceType: _selectedServiceType,
          company: _companyId,
          payRate: payRate,
          deliveryStyle: _deliveryStyle,
          fileNumber: null,
          status: 'pending',
          address: orNull(_addressController),
          city: orNull(_cityController),
          state: orNull(_stateController),
          postalCode: orNull(_zipController),
          latitude: hasCoords ? lat : null,
          longitude: hasCoords ? lng : null,
        )).future);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile created successfully')),
          );
          // Hand the new profile back to whichever flow opened this screen
          // (e.g. the Upload flow can auto-select it) — never an Attempt.
          ref.invalidate(profilesProvider);
          context.pop(created);
          return;
        }
      }

      // Refresh profiles list
      ref.invalidate(profilesProvider);

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Shared card shell — matches the Upload screen's `_card()` exactly. ─────
  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
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

  // ── Section header: colored icon badge + title (+ required/done state) —
  // matches the Upload screen's `_sectionLabel()` exactly. ───────────────────
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
                      colors: [Color(0x1F4A90E2), Color(0x334A90E2)],
                    ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: done
                  ? [
                      BoxShadow(
                        color: _successGreen.withValues(alpha: 0.25),
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
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (required && !done) ...[
                  const SizedBox(width: 4),
                  const Text(
                    '*',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _errorRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (required && !done)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Required',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _errorRed,
                ),
              ),
            ),
        ],
      );

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _inkMuted,
          letterSpacing: -0.1,
        ),
      );

  Widget _helper(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12.5, height: 1.35, color: _inkMuted),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Container(height: 1, color: _separator),
      );

  InputDecoration _deco({
    required String hint,
    IconData? icon,
    TextEditingController? voiceFor,
    VoiceFillMode voiceMode = VoiceFillMode.replace,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
        prefixIcon:
            icon != null ? Icon(icon, size: 18, color: _inkSubtle) : null,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
        suffixIcon: voiceFor != null
            ? VoiceMicButton(controller: voiceFor, mode: voiceMode)
            : null,
        filled: true,
        fillColor: _canvas,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      );

  TextStyle get _fieldStyle => const TextStyle(fontSize: 14, color: _ink);

  Widget _dropdownShell({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: DropdownButtonHideUnderline(child: child),
      );

  Widget _metaChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _actionTile({
    required VoidCallback? onTap,
    required IconData icon,
    required String label,
    bool primary = false,
    bool loading = false,
  }) {
    final bg = primary ? _accent : _canvas;
    final fg = primary ? Colors.white : _accent;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Identity: name + status ───────────────────────────────────────────────
  Widget _buildIdentityCard(bool nameDone) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Profile Name',
              Icons.person_rounded,
              required: true,
              done: nameDone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: const [TitleCaseInputFormatter()],
              style: _fieldStyle,
              decoration: _deco(
                hint: 'Enter profile name or tap the mic',
                icon: Icons.person_outline_rounded,
                voiceFor: _nameController,
              ),
            ),
            _divider(),
            _fieldLabel('Status'),
            const SizedBox(height: 6),
            Text(
              _isEditing
                  ? profileStatusLabel(_status)
                  : 'Pending',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            _helper(_statusHelper),
          ],
        ),
      );

  // ── Company (+ live diligence / priority summary) ─────────────────────────
  Widget _buildCompanyCard() {
    final company = companyOrDefault(_companyId);
    final priorities = company.priorityCategories
        .map((c) => c.label)
        .join(' · ');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Company', Icons.business_rounded),
          const SizedBox(height: 6),
          _helper('Sets available priorities, diligence rules, and rates.'),
          const SizedBox(height: 12),
          _dropdownShell(
            child: DropdownButtonFormField<String>(
              key: ValueKey(_companyId),
              initialValue: _companyId,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              style: _fieldStyle,
              icon: const Icon(Icons.expand_more_rounded, color: _inkSubtle),
              items: [
                for (final c in kCompanies)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) {
                if (v == null) return;
                HapticFeedback.selectionClick();
                setState(() {
                  _companyId = v;
                  _selectedServiceType = defaultPriorityForCompany(v);
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel('Priority Level'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in company.priorityCategories)
                ChoiceChip(
                  label: Text(c.label),
                  selected: _selectedServiceType == c.value,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedServiceType = c.value);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _fieldLabel('Delivery Style'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in kDeliveryStyles)
                ChoiceChip(
                  label: Text(s),
                  selected: _deliveryStyle == s,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _deliveryStyle = s);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaChip(
                Icons.replay_rounded,
                '${company.attemptsForDiligence} diligence attempts',
              ),
              _metaChip(Icons.bolt_rounded, priorities),
            ],
          ),
        ],
      ),
    );
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Widget _buildMiniMap(LatLng point) {
    return GestureDetector(
      onTap: _pickOnMap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 156,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    key: ValueKey(
                      '${point.latitude.toStringAsFixed(5)},'
                      '${point.longitude.toStringAsFixed(5)}',
                    ),
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      AppMapTiles.layer(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 36,
                            height: 36,
                            child: Container(
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
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Tap to edit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Profile Location',
              Icons.location_on_rounded,
              done: _hasLocation,
            ),
            const SizedBox(height: 6),
            _helper('Optional. Where this profile’s work is associated.'),
            if (_previewPoint != null) ...[
              const SizedBox(height: 12),
              _buildMiniMap(_previewPoint!),
            ],
            if (_hasLocation && _locationSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _successGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _successGreen.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: _successGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationSummary,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _actionTile(
                    onTap: _pickOnMap,
                    icon: Icons.map_outlined,
                    label: _hasLocation ? 'Edit on Map' : 'Set on Map',
                    primary: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _actionTile(
                    onTap: _locatingCurrent ? null : _useCurrentLocation,
                    icon: Icons.my_location_rounded,
                    label: 'Current',
                    loading: _locatingCurrent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              style: _fieldStyle,
              decoration: _deco(
                hint: 'Address',
                icon: Icons.apartment_rounded,
                voiceFor: _addressController,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    style: _fieldStyle,
                    decoration: _deco(hint: 'City'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.characters,
                    style: _fieldStyle,
                    decoration: _deco(hint: 'State'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zipController,
              keyboardType: TextInputType.number,
              style: _fieldStyle,
              decoration: _deco(hint: 'ZIP Code'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _coordsExpanded = !_coordsExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _coordsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: _inkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _coordsExpanded
                          ? 'Hide coordinates'
                          : 'Show coordinates',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_coordsExpanded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: _fieldStyle,
                      decoration: _deco(hint: 'Latitude'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: _fieldStyle,
                      decoration: _deco(hint: 'Longitude'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
            if (_hasLocation) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _clearLocation,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 15, color: _inkMuted),
                    SizedBox(width: 5),
                    Text(
                      'Clear Location',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  // ── Optional details ──────────────────────────────────────────────────────
  Widget _buildDetailsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Payout', Icons.attach_money_rounded, done: _payoutDone),
            const SizedBox(height: 6),
            _helper('Required. Standing payout for this profile.'),
            const SizedBox(height: 14),
            _fieldLabel('Payout (\$)'),
            const SizedBox(height: 8),
            TextField(
              controller: _payRateController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: _fieldStyle,
              decoration: _deco(
                hint: 'e.g. 50',
                icon: Icons.attach_money_rounded,
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 14),
              _fieldLabel('Note'),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [SentenceCaseInputFormatter()],
                style: _fieldStyle,
                decoration: _deco(
                  hint: 'Add a note about this profile',
                  icon: Icons.description_outlined,
                  voiceFor: _noteController,
                  voiceMode: VoiceFillMode.append,
                ),
              ),
            ],
          ],
        ),
      );

  bool get _nameDone => _nameController.text.trim().isNotEmpty;
  bool get _payoutDone =>
      int.tryParse(_payRateController.text.trim()) != null;
  bool get _deliveryDone =>
      _deliveryStyle != null && kDeliveryStyles.contains(_deliveryStyle);

  bool get _canAdvance {
    if (_step == 0) return _nameDone;
    if (_step == 1) return _deliveryDone && _payoutDone;
    return true;
  }

  bool get _requiredComplete =>
      _nameDone && _deliveryDone && _payoutDone;

  void _goNext() {
    if (!_canAdvance) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      _saveProfile();
    }
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  Widget _buildStepHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _stepCount; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i <= _step ? _accent : _separator,
                    ),
                  ),
                _stepDot(i),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Step ${_step + 1} of $_stepCount',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _accent,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stepTitles[_step],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stepSubtitles[_step],
            style: const TextStyle(
              fontSize: 13.5,
              color: _inkMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDot(int index) {
    final done = index < _step;
    final active = index == _step;
    return GestureDetector(
      onTap: () {
        if (index == _step) return;
        // Only allow revisiting earlier steps from the indicator.
        if (index < _step) {
          FocusScope.of(context).unfocus();
          HapticFeedback.selectionClick();
          setState(() => _step = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 28 : 22,
        height: active ? 28 : 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: (done || active) ? _btnGradient : null,
          color: (done || active) ? null : _separator,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : _inkSubtle,
                ),
              ),
      ),
    );
  }

  Widget _buildStepBody() {
    final nameDone = _nameDone;
    switch (_step) {
      case 0:
        return _buildIdentityCard(nameDone);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpeakFillBanner(
              hint: 'Say a company and pay, e.g. “First Legal, 125 dollars”',
              onDraft: _applyDraft,
            ),
            const SizedBox(height: 12),
            _buildCompanyCard(),
            _buildDetailsCard(),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpeakFillBanner(
              hint: 'Say the street, city, state, and ZIP',
              onDraft: _applyDraft,
            ),
            const SizedBox(height: 12),
            _buildLocationCard(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Sticky stepper CTA ────────────────────────────────────────────────────
  Widget _buildStickyFooter() {
    final canPrimary =
        _step < _stepCount - 1 ? _canAdvance : _requiredComplete;
    final primaryLabel = _isEditing ? 'Update Profile' : 'Create Profile';
    final primaryIcon =
        _isEditing ? Icons.check_rounded : Icons.add_rounded;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(
          top: BorderSide(color: _separator, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 54,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: (!_isLoading && canPrimary) ? _btnGradient : null,
                color: (_isLoading || !canPrimary) ? _separator : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: (!_isLoading && canPrimary)
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: (_isLoading || !canPrimary) ? null : _saveProfile,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _inkMuted,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                primaryIcon,
                                size: 20,
                                color: canPrimary
                                    ? Colors.white
                                    : _inkSubtle,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                primaryLabel,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: canPrimary
                                      ? Colors.white
                                      : _inkSubtle,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Name, company, and priority are required. Location is optional.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _inkSubtle,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Profile' : 'New Profile',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: _surface,
        foregroundColor: _ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _isLoading ? null : () => context.pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _separator),
        ),
      ),
      backgroundColor: _canvas,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SpeakFillBanner(
                    hint: 'Say a name, company, address, or pay rate',
                    onDraft: _applyDraft,
                  ),
                  const SizedBox(height: 12),
                  _buildIdentityCard(_nameDone),
                  _buildCompanyCard(),
                  _buildDetailsCard(),
                  _buildLocationCard(),
                ],
              ),
            ),
          ),
          _buildStickyFooter(),
        ],
      ),
    );
  }
}
