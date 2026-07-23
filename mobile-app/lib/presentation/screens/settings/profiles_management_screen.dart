import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/location_service.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
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
  late TextEditingController _nameController;
  late TextEditingController _noteController;
  late TextEditingController _payRateController;
  String _selectedServiceType = 'standard';
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

  @override
  void initState() {
    super.initState();
    final p = widget.profileToEdit;
    _nameController = TextEditingController(text: p?.name ?? '');
    _noteController = TextEditingController(text: p?.note ?? '');
    _payRateController =
        TextEditingController(text: p?.payRate?.toString() ?? '');
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _payRateController.dispose();
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
    });
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final payRate = int.tryParse(_payRateController.text.trim());
    // Only treated as set when BOTH parse — a partially-edited pair is
    // treated as "not set" rather than silently saving a mismatched point.
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    final hasCoords = lat != null && lng != null;

    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    try {
      if (widget.profileToEdit != null) {
        // Update existing profile
        await ref.read(updateProfileProvider((
          profileId: widget.profileToEdit!.id,
          name: _nameController.text,
          serviceType: _selectedServiceType,
          note: _noteController.text.isEmpty ? null : _noteController.text,
          payRate: payRate,
          status: _status,
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
          name: _nameController.text,
          serviceType: _selectedServiceType,
          payRate: payRate,
          status: _status,
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

  @override
  Widget build(BuildContext context) {
    const grayBg = Color(0xFFF8FAFC);
    const grayText = Color(0xFF6B7280);
    const grayBorder = Color(0xFFE2E8F0);
    const graySubtle = Color(0xFF94A3B8);
    final accent = Theme.of(context).colorScheme.primary;

    InputDecoration deco({
      required String hint,
      IconData? icon,
    }) =>
        InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: graySubtle),
          prefixIcon: icon != null ? Icon(icon, color: graySubtle) : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: grayBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: grayBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        );

    Widget label(String text) => Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: grayText,
              ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profileToEdit != null ? 'Edit Profile' : 'Add Profile',
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: grayText,
      ),
      backgroundColor: grayBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Name
            label('Profile Name'),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseInputFormatter()],
              decoration: deco(
                hint: 'Enter profile name',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 24),

            // Service level is chosen per-photo during upload, not on the
            // profile, so there is no service-level picker here (it would be a
            // duplicate of the upload screen's picker).

            // Status — independent of any Attempt/Photo status.
            label('Status'),
            const SizedBox(height: 6),
            const Text(
              'The Profile/job has already been created, but field work has '
              'not yet been attempted.',
              style: TextStyle(fontSize: 12, color: graySubtle),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: deco(hint: 'Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Active')),
                DropdownMenuItem(
                  value: 'awaiting_attempt',
                  child: Text('Awaiting Attempt'),
                ),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 24),

            // ── Profile Location ────────────────────────────────────────────
            label('Profile Location'),
            const SizedBox(height: 6),
            const Text(
              'Physical location where this work/profile is associated. '
              'This can be set before an attempt is made.',
              style: TextStyle(fontSize: 12, color: graySubtle),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickOnMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                        _hasLocation ? 'Change on Map' : 'Search / Pick on Map'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: grayBorder, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _locatingCurrent ? null : _useCurrentLocation,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    side: const BorderSide(color: grayBorder, width: 1.5),
                  ),
                  child: _locatingCurrent
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              decoration: deco(
                hint: 'Address',
                icon: Icons.apartment_rounded,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    decoration: deco(hint: 'City'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: deco(hint: 'State'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zipController,
              keyboardType: TextInputType.number,
              decoration: deco(hint: 'ZIP Code'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                    decoration: deco(hint: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                    decoration: deco(hint: 'Longitude'),
                  ),
                ),
              ],
            ),
            if (_hasLocation) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clearLocation,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Clear Location'),
                  style: TextButton.styleFrom(foregroundColor: grayText),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Pay Rate — standing rate summed across all profiles to produce
            // "Total Available Earnings" on the Earnings screen.
            label('Pay Rate (Optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _payRateController,
              keyboardType: TextInputType.number,
              decoration:
                  deco(hint: 'Enter pay rate', icon: Icons.attach_money_rounded),
            ),
            const SizedBox(height: 24),

            // Note
            label('Note (Optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: const [SentenceCaseInputFormatter()],
              decoration: deco(
                hint: 'Add a note about this profile',
                icon: Icons.description_outlined,
              ),
            ),
            const SizedBox(height: 36),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      widget.profileToEdit != null
                          ? 'Update Profile'
                          : 'Create Profile',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Cancel Button
            OutlinedButton(
              onPressed: _isLoading ? null : () => context.pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: grayBorder, width: 1.5),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
