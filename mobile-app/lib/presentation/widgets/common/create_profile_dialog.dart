import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Shared "New Profile" dialog used everywhere a profile can be created
/// (upload screen, map-tap upload sheet, and the Settings profiles list).
/// Keeps profile creation visually and behaviourally identical across the app.
///
/// Returns the created [ProfileModel] on success, or `null` if the user
/// cancelled or creation failed. The caller does not need to invalidate
/// [profilesProvider] — the dialog already does so on success.
///
/// When [initialCompanyId] is set (e.g. from the upload company selector),
/// that company is pre-selected in the dropdown.
Future<ProfileModel?> showCreateProfileDialog(
  BuildContext context, {
  String? initialCompanyId,
}) {
  return showDialog<ProfileModel>(
    context: context,
    builder: (_) => _CreateProfileDialog(initialCompanyId: initialCompanyId),
  );
}

class _CreateProfileDialog extends ConsumerStatefulWidget {
  const _CreateProfileDialog({this.initialCompanyId});

  final String? initialCompanyId;

  @override
  ConsumerState<_CreateProfileDialog> createState() =>
      _CreateProfileDialogState();
}

class _CreateProfileDialogState extends ConsumerState<_CreateProfileDialog> {
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _canvas = Color(0xFF1C222E);
  static const Color _inkMuted = Color(0xFF94A3B8);

  final _nameCtrl = TextEditingController();
  late String _companyId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _companyId = companyById(widget.initialCompanyId)?.id ?? kDefaultCompanyId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      // Service level is chosen per-photo during upload, not on the profile,
      // so new profiles start at the company default and the upload flow owns
      // the priority/service selection (filtered by company).
      final created = await ref.read(createProfileProvider((
        name: name,
        serviceType: defaultPriorityForCompany(_companyId),
        company: _companyId,
        payRate: null,
        status: null,
        address: null,
        city: null,
        state: null,
        postalCode: null,
        latitude: null,
        longitude: null,
      )).future);
      ref.invalidate(profilesProvider);
      if (mounted) Navigator.pop(context, created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create profile')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('New Profile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      // Scrollable so the on-screen keyboard can never hide the input or
      // the action buttons on smaller devices.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseInputFormatter()],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                hintText: 'Profile name',
                filled: true,
                fillColor: _canvas,
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
            const SizedBox(height: 14),
            const Text(
              'Company',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _companyId,
              decoration: InputDecoration(
                filled: true,
                fillColor: _canvas,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                for (final c in kCompanies)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _companyId = v);
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Priority levels follow this company.',
              style: TextStyle(fontSize: 12, color: _inkMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
