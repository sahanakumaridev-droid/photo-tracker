import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/spoken_parser.dart';
import '../../../core/utils/file_number.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/delivery_style.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/speak_fill_banner.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../../widgets/common/company_dropdown.dart';

/// Shared "New Profile" sheet used everywhere a profile can be created.
///
/// Required: Profile Name, File Number, Company, Priority, Delivery Style,
/// Payout.
Future<ProfileModel?> showCreateProfileDialog(
  BuildContext context, {
  String? initialCompanyId,
  double? latitude,
  double? longitude,
  String? address,
  bool hotRoute = false,
}) {
  return showModalBottomSheet<ProfileModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    // The shell paints the tab bar above nested routes. Root navigator
    // keeps Create profile above that bar.
    useRootNavigator: true,
    builder: (_) => _CreateProfileSheet(
      initialCompanyId: initialCompanyId,
      latitude: latitude,
      longitude: longitude,
      address: address,
      hotRoute: hotRoute,
    ),
  );
}

class _CreateProfileSheet extends ConsumerStatefulWidget {
  const _CreateProfileSheet({
    this.initialCompanyId,
    this.latitude,
    this.longitude,
    this.address,
    this.hotRoute = false,
  });

  final String? initialCompanyId;
  final double? latitude;
  final double? longitude;
  final String? address;
  final bool hotRoute;

  @override
  ConsumerState<_CreateProfileSheet> createState() =>
      _CreateProfileSheetState();
}

class _CreateProfileSheetState extends ConsumerState<_CreateProfileSheet> {
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accentSoft = Color(0x1F4A90E2);
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A2130);
  static const Color _inkMuted = Color(0xFF5C6778);
  static const Color _inkSubtle = Color(0xFF8B95A5);
  static const Color _separator = Color(0xFFE3E7EE);

  final _nameCtrl = TextEditingController();
  final _fileCtrl = TextEditingController();
  final _payCtrl = TextEditingController();
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _countyCtrl;
  late final TextEditingController _zipCtrl;
  late String _companyId;
  late String _priority;
  String? _deliveryStyle;
  bool _saving = false;
  String? _error;
  List<({String label, double lat, double lng})> _addressSuggestions = [];
  int _suggestToken = 0;
  Timer? _suggestTimer;
  bool _applyingSuggestion = false;
  double? _pinLat;
  double? _pinLng;
  String _heldAddress = '';

  @override
  void initState() {
    super.initState();
    _companyId = companyById(widget.initialCompanyId)?.id ?? kDefaultCompanyId;
    _priority = defaultPriorityForCompany(_companyId);
    _addressCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _stateCtrl = TextEditingController();
    _countyCtrl = TextEditingController();
    _zipCtrl = TextEditingController();
    _pinLat = widget.latitude;
    _pinLng = widget.longitude;
    _fillFromPassedAddress(widget.address);
    _heldAddress = _normalizeAddress(_addressCtrl.text);
    if (widget.hotRoute) {
      _addressCtrl.addListener(_onAddressEdited);
      if (widget.latitude != null && widget.longitude != null) {
        unawaited(_prefillFromMap());
      }
    }
    _nameCtrl.addListener(() => setState(() {}));
    _fileCtrl.addListener(() => setState(() {}));
    _payCtrl.addListener(() => setState(() {}));
    _addressCtrl.addListener(() => setState(() {}));
    _cityCtrl.addListener(() => setState(() {}));
    _stateCtrl.addListener(() => setState(() {}));
    _countyCtrl.addListener(() => setState(() {}));
    _zipCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _nameCtrl.dispose();
    _fileCtrl.dispose();
    _payCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _countyCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  void _onAddressEdited() {
    if (!widget.hotRoute || _applyingSuggestion) return;
    final typed = _addressCtrl.text.trim();
    _suggestTimer?.cancel();
    if (typed.length < 3) {
      if (_addressSuggestions.isNotEmpty && mounted) {
        setState(() => _addressSuggestions = []);
      }
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadAddressSuggestions(typed));
    });
  }

  Future<void> _loadAddressSuggestions(String typed) async {
    final token = ++_suggestToken;
    final hits = await LocationService.suggestPlaces(typed);
    if (!mounted || token != _suggestToken) return;
    if (_addressCtrl.text.trim() != typed) return;
    setState(() {
      _addressSuggestions = [
        for (final hit in hits)
          if (hit.label.toLowerCase() != typed.toLowerCase()) hit,
      ];
    });
  }

  String _normalizeAddress(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  void _pickAddress(({String label, double lat, double lng}) hit) {
    _suggestTimer?.cancel();
    _suggestToken++;
    _applyingSuggestion = true;
    final label = hit.label.trim();
    _addressCtrl.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    _pinLat = hit.lat;
    _pinLng = hit.lng;
    _heldAddress = _normalizeAddress(label);
    _applyingSuggestion = false;
    setState(() => _addressSuggestions = []);
  }

  static final _streetOk = RegExp(
    r'^(?:P\.?\s*O\.?\s*Box\s+\d+[A-Za-z0-9-]*|\d+\s+\S.+|[A-Za-z0-9].{2,})$',
    caseSensitive: false,
  );
  static final _cityOk = RegExp(
    r"^[A-Za-z][A-Za-z .'-]+,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?$",
  );

  Future<void> _prefillFromMap() async {
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat == null || lng == null) return;
    final place = await LocationService.reverseGeocodeDetailed(lat, lng);
    if (!mounted || _applyingSuggestion) return;
    _applyingSuggestion = true;
    final lines = <String>[
      if ((place.street ?? '').isNotEmpty) place.street!,
      [
        if ((place.city ?? '').isNotEmpty) place.city!,
        [
          if ((place.state ?? '').isNotEmpty) place.state!,
          if ((place.zip ?? '').isNotEmpty) place.zip!,
        ].join(' '),
      ].where((s) => s.trim().isNotEmpty).join(', '),
      if ((place.county ?? '').isNotEmpty &&
          place.county != place.zip &&
          place.county != place.city)
        place.county!,
    ].where((s) => s.trim().isNotEmpty);
    if (lines.isNotEmpty) _addressCtrl.text = lines.join('\n');
    _heldAddress = _normalizeAddress(_addressCtrl.text);
    _applyingSuggestion = false;
    if (mounted) setState(() {});
  }

  void _applyCityLine(String line) {
    final match = RegExp(
      r'^(.+?),\s*([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)$',
    ).firstMatch(line.trim());
    if (match == null) {
      if (line.trim().isNotEmpty) _cityCtrl.text = line.trim();
      return;
    }
    _cityCtrl.text = match.group(1)!.trim();
    _stateCtrl.text = match.group(2)!.toUpperCase();
    _zipCtrl.text = match.group(3)!;
  }

  String get _cityLine {
    final city = _cityCtrl.text.trim();
    final state = _stateCtrl.text.trim().toUpperCase();
    final zip = _zipCtrl.text.trim();
    if (city.isEmpty) return '';
    if (state.isEmpty && zip.isEmpty) return city;
    return '$city, $state $zip'.trim();
  }
  String? _addressError() {
    if (_addressCtrl.text.trim().isEmpty) return 'Add the address.';
    return null;
  }

  void _fillFromPassedAddress(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return;
    _addressCtrl.text = text;
  }

  bool get _fileNa =>
      _fileCtrl.text.trim().toUpperCase() == kFileNumberNA;

  bool get _ready =>
      widget.hotRoute
          ? _nameCtrl.text.trim().isNotEmpty &&
              _fileCtrl.text.trim().isNotEmpty &&
              _addressCtrl.text.trim().isNotEmpty &&
              int.tryParse(_payCtrl.text.trim()) != null
          : _nameCtrl.text.trim().isNotEmpty &&
              _fileCtrl.text.trim().isNotEmpty &&
              _deliveryStyle != null;

  Future<void> _create() async {
    if (!_ready || _saving) return;
    final fn = _fileCtrl.text.trim();
    final name = _nameCtrl.text.trim().toLowerCase();
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    final nameTaken = profiles.any(
      (p) => p.name.trim().toLowerCase() == name,
    );
    if (nameTaken) {
      setState(() => _error = 'This name already exists. Use a new name.');
      return;
    }
    final others = profiles.map((p) => p.fileNumber);
    if (fileNumberAlreadyUsed(fn, others)) {
      setState(() => _error = 'This file number already exists');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var lat = _pinLat;
      var lng = _pinLng;
      final street = _addressCtrl.text.trim();
      if (widget.hotRoute) {
        final addressError = _addressError();
        if (addressError != null) {
          setState(() {
            _saving = false;
            _error = addressError;
          });
          return;
        }
        final typed = _normalizeAddress(street);
        final addressChanged = typed.isNotEmpty && typed != _heldAddress;
        if (addressChanged || lat == null || lng == null) {
          final hit = await LocationService.searchPlace(street);
          if (!mounted) return;
          if (hit == null) {
            setState(() {
              _saving = false;
              _error =
                  'Could not find that address. Choose a suggestion so the pin matches what you typed.';
            });
            return;
          }
          lat = hit.lat;
          lng = hit.lng;
        }
      }
      if (widget.hotRoute &&
          (lat == null ||
              lng == null ||
              !LocationService.isInUnitedStates(lat, lng))) {
        setState(() {
          _saving = false;
          _error = 'A hot route can only be created in the United States.';
        });
        return;
      }
      final created = await ref.read(createProfileProvider((
        name: _nameCtrl.text.trim(),
        serviceType: _priority,
        company: _companyId,
        payRate: widget.hotRoute
            ? int.parse(_payCtrl.text.trim())
            : null,
        deliveryStyle: widget.hotRoute ? null : _deliveryStyle,
        fileNumber: fn,
        status: 'pending',
        address: widget.hotRoute ? street : widget.address,
        city: null,
        state: null,
        postalCode: null,
        latitude: lat,
        longitude: lng,
      )).future);
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context, rootNavigator: true).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applyDraft(SpokenDraft d) {
    setState(() {
      if (d.name != null && d.name!.trim().isNotEmpty) {
        _nameCtrl.text = d.name!;
      }
      if (d.companyId != null) {
        _companyId = d.companyId!;
        if (!companyOrDefault(_companyId).allowsPriority(_priority)) {
          _priority = defaultPriorityForCompany(_companyId);
        }
      }
      if (d.priority != null &&
          companyOrDefault(_companyId).allowsPriority(d.priority)) {
        _priority = d.priority!;
      }
      if (d.payRate != null) {
        _payCtrl.text = '${d.payRate}';
      }
    });
  }

  InputDecoration _deco({String? hint, Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkSubtle, fontSize: 15),
        filled: true,
        fillColor: _canvas,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  Widget _section({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _separator),
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
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : _canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent : _separator,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? _accent : _inkMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = companyOrDefault(_companyId);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Material(
            color: _canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: _inkMuted,
                      ),
                      Expanded(
                        child: Text(
                          widget.hotRoute ? 'Hot route' : 'New Profile',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      children: [
                        SpeakFillBanner(
                          hint: 'Say “Jane Doe, First Legal, 50 dollars”',
                          onDraft: _applyDraft,
                        ),
                        const SizedBox(height: 12),
                        _section(
                          title: 'Identity',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profile name',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _inkMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameCtrl,
                                autofocus: true,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: const [
                                  TitleCaseInputFormatter()
                                ],
                                textInputAction: TextInputAction.next,
                                decoration: _deco(
                                  hint: 'Profile name',
                                  suffix: VoiceMicButton(controller: _nameCtrl),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'File number',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _inkMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _fileCtrl,
                                      enabled: !_fileNa,
                                      textInputAction: TextInputAction.next,
                                      decoration: _deco(
                                        hint: 'Dispatcher file number',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      if (_fileNa) {
                                        _fileCtrl.clear();
                                      } else {
                                        _fileCtrl.text = kFileNumberNA;
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _fileNa ? _accentSoft : _canvas,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _fileNa ? _accent : _separator,
                                          width: _fileNa ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Text(
                                        kFileNumberNA,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: _fileNa ? _accent : _inkMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          title: 'Company',
                          child: CompanyDropdown(
                            value: _companyId,
                            onChanged: (v) {
                              setState(() {
                                _companyId = v;
                                if (!companyOrDefault(v)
                                    .allowsPriority(_priority)) {
                                  _priority = defaultPriorityForCompany(v);
                                }
                              });
                            },
                          ),
                        ),
                        if (widget.hotRoute) ...[
                          const SizedBox(height: 12),
                          _section(
                            title: 'Priority',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in company.priorityCategories)
                                  _chip(
                                    label: c.label,
                                    selected: _priority == c.value,
                                    onTap: () =>
                                        setState(() => _priority = c.value),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _section(
                            title: 'Address',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _addressCtrl,
                                  minLines: 3,
                                  maxLines: 4,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: _deco(
                                    hint: '833 Mission Street\nSan Francisco, CA 94108',
                                  ),
                                ),
                                if (_addressSuggestions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  for (final suggestion in _addressSuggestions)
                                    InkWell(
                                      onTap: () => _pickAddress(suggestion),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          suggestion.label,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: _ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _section(
                            title: 'Payout',
                            child: TextField(
                              controller: _payCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _deco(hint: r'e.g. $50'),
                            ),
                          ),
                        ] else ...[
                        const SizedBox(height: 12),
                        _section(
                          title: 'Priority',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in company.priorityCategories)
                                _chip(
                                  label: c.label,
                                  selected: _priority == c.value,
                                  onTap: () =>
                                      setState(() => _priority = c.value),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          title: 'Delivery style',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in kDeliveryStyles)
                                _chip(
                                  label: s,
                                  selected: _deliveryStyle == s,
                                  onTap: () =>
                                      setState(() => _deliveryStyle = s),
                                ),
                            ],
                          ),
                        ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  decoration: const BoxDecoration(
                    color: _surface,
                    border: Border(top: BorderSide(color: _separator)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_saving || !_ready) ? null : _create,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _separator,
                        disabledForegroundColor: _inkSubtle,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _ready
                                  ? (widget.hotRoute
                                      ? 'Create hot route'
                                      : 'Create profile')
                                  : 'Fill required fields',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
