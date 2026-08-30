import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/spoken_parser.dart';
import '../../../core/utils/file_number.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/delivery_style.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/speak_fill_banner.dart';
import '../../widgets/ai/voice_mic_button.dart';

/// Shared "New Profile" sheet used everywhere a profile can be created.
///
/// Required: Profile Name, File Number, Company, Priority, Delivery Style,
/// Payout.
Future<ProfileModel?> showCreateProfileDialog(
  BuildContext context, {
  String? initialCompanyId,
}) {
  return showModalBottomSheet<ProfileModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _CreateProfileSheet(initialCompanyId: initialCompanyId),
  );
}

class _CreateProfileSheet extends ConsumerStatefulWidget {
  const _CreateProfileSheet({this.initialCompanyId});

  final String? initialCompanyId;

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
    _fileCtrl.addListener(() => setState(() {}));
    _payCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fileCtrl.dispose();
    _payCtrl.dispose();
    super.dispose();
  }

  bool get _fileNa =>
      _fileCtrl.text.trim().toUpperCase() == kFileNumberNA;

  bool get _ready =>
      _nameCtrl.text.trim().isNotEmpty &&
      _fileCtrl.text.trim().isNotEmpty &&
      _deliveryStyle != null &&
      int.tryParse(_payCtrl.text.trim()) != null;

  Future<void> _create() async {
    if (!_ready || _saving) return;
    final fn = _fileCtrl.text.trim();
    final others = (ref.read(profilesProvider).valueOrNull ?? [])
        .map((p) => p.fileNumber);
    if (fileNumberAlreadyUsed(fn, others)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This file number already exists')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await ref.read(createProfileProvider((
        name: _nameCtrl.text.trim(),
        serviceType: _priority,
        company: _companyId,
        payRate: int.parse(_payCtrl.text.trim()),
        deliveryStyle: _deliveryStyle,
        fileNumber: fn,
        status: 'pending',
        address: null,
        city: null,
        state: null,
        postalCode: null,
        latitude: null,
        longitude: null,
      )).future);
      ref.invalidate(profilesProvider);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
                      const Expanded(
                        child: Text(
                          'New Profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                          child: DropdownButtonFormField<String>(
                            initialValue: _companyId,
                            decoration: _deco(),
                            dropdownColor: _surface,
                            items: [
                              for (final c in kCompanies)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
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
                  child: SizedBox(
                    height: 52,
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
                                  ? 'Create profile'
                                  : 'Fill required fields',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
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
}
