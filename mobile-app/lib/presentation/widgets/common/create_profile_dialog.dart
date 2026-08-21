import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/spoken_parser.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/delivery_style.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/speak_fill_banner.dart';
import '../../widgets/ai/voice_mic_button.dart';

/// Shared "New Profile" dialog used everywhere a profile can be created
/// (upload screen, map-tap upload sheet, and the Settings profiles list).
/// Keeps profile creation visually and behaviourally identical across the app.
///
/// Required: Profile Name, Company, Priority Level, Delivery Style, Payout.
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
  static const Color _canvas = Color(0xFFFFFFFF);
  static const Color _inkMuted = Color(0xFF5C6778);

  final _nameCtrl = TextEditingController();
  final _payCtrl = TextEditingController();
  late String _companyId;
  late String _priority;
  String? _deliveryStyle;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _companyId = companyById(widget.initialCompanyId)?.id ?? kDefaultCompanyId;
    _priority = defaultPriorityForCompany(_companyId);
    _nameCtrl.addListener(() => setState(() {}));
    _payCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _payCtrl.dispose();
    super.dispose();
  }

  bool get _ready =>
      _nameCtrl.text.trim().isNotEmpty &&
      _deliveryStyle != null &&
      int.tryParse(_payCtrl.text.trim()) != null;

  Future<void> _create() async {
    if (!_ready || _saving) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(createProfileProvider((
        name: _nameCtrl.text.trim(),
        serviceType: _priority,
        company: _companyId,
        payRate: int.parse(_payCtrl.text.trim()),
        deliveryStyle: _deliveryStyle,
        status: 'awaiting_attempt',
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
        filled: true,
        fillColor: _canvas,
        suffixIcon: suffix,
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
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _inkMuted,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final company = companyOrDefault(_companyId);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('New Profile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SpeakFillBanner(
              hint: 'Say “Jane Doe, First Legal, 50 dollars”',
              onDraft: _applyDraft,
            ),
            const SizedBox(height: 12),
            _label('Profile Name'),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseInputFormatter()],
              textInputAction: TextInputAction.next,
              decoration: _deco(
                hint: 'Profile name',
                suffix: VoiceMicButton(controller: _nameCtrl),
              ),
            ),
            const SizedBox(height: 14),
            _label('Company'),
            DropdownButtonFormField<String>(
              initialValue: _companyId,
              decoration: _deco(),
              items: [
                for (final c in kCompanies)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _companyId = v;
                  if (!companyOrDefault(v).allowsPriority(_priority)) {
                    _priority = defaultPriorityForCompany(v);
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            _label('Priority Level'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in company.priorityCategories)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _priority == c.value,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _priority = c.value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _label('Delivery Style'),
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
            const SizedBox(height: 14),
            _label('Payout (\$)'),
            TextField(
              controller: _payCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco(hint: 'e.g. 50'),
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
          onPressed: (_saving || !_ready) ? null : _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            disabledBackgroundColor: const Color(0xFFE3E7EE),
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
