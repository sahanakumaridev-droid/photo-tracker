import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/category.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Shared "New Profile" dialog used everywhere a profile can be created
/// (upload screen, map-tap upload sheet, and the Settings profiles list).
/// Keeps profile creation visually and behaviourally identical across the app.
///
/// Returns the created [ProfileModel] on success, or `null` if the user
/// cancelled or creation failed. The caller does not need to invalidate
/// [profilesProvider] — the dialog already does so on success.
Future<ProfileModel?> showCreateProfileDialog(BuildContext context) {
  return showDialog<ProfileModel>(
    context: context,
    builder: (_) => const _CreateProfileDialog(),
  );
}

class _CreateProfileDialog extends ConsumerStatefulWidget {
  const _CreateProfileDialog();

  @override
  ConsumerState<_CreateProfileDialog> createState() =>
      _CreateProfileDialogState();
}

class _CreateProfileDialogState extends ConsumerState<_CreateProfileDialog> {
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _canvas = Color(0xFFF7F5FF);
  static const Color _inkMuted = Color(0xFF6B7280);

  final _nameCtrl = TextEditingController();
  final _payRateCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _payRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _saving) return;
    final payRate = int.tryParse(_payRateCtrl.text.trim());
    setState(() => _saving = true);
    try {
      // Service level is chosen per-photo during upload, not on the profile,
      // so new profiles start at the default and the upload flow owns the
      // priority/service selection.
      final created = await ref.read(createProfileProvider((
        name: name,
        serviceType: kDefaultCategory,
        payRate: payRate,
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
            const SizedBox(height: 6),
            const Text(
              'You\'ll choose the service level when you upload a photo.',
              style: TextStyle(fontSize: 12, color: _inkMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _payRateCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                hintText: 'Pay rate (optional)',
                prefixText: r'$',
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
