part of 'attempt_composer_screen.dart';

extension _AttemptComposerPickersExt on _AttemptComposerScreenState {
  void _showProfilePicker(List<ProfileModel> profiles) {
    HapticFeedback.lightImpact();
    final searchCtrl = TextEditingController();
    final openProfiles = profiles.where((p) => p.canAddAttempts).toList();
    final nearbyIds = controller.nearbyProfileIds(ref);
    final nearbyProfiles =
        openProfiles.where((p) => nearbyIds.contains(p.id)).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final nearby = query.isEmpty
              ? nearbyProfiles
              : nearbyProfiles
                  .where((p) => p.name.toLowerCase().contains(query))
                  .toList();

          Future<void> select(ProfileModel p) async {
            if (!widget.isEditing) {
              final ok = await ensureCanStartNewAttempt(
                context,
                ref,
                profileId: p.id,
                knownCount: p.attemptsCount,
              );
              if (!ok || !mounted) return;
            }
            HapticFeedback.selectionClick();
            controller.setSelectedProfile(p, ref: ref);
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _separator,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select profile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(fontSize: 14, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Search profiles…',
                      hintStyle: const TextStyle(color: _inkSubtle),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: _inkSubtle),
                      filled: true,
                      fillColor: _canvas,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _createProfile();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded,
                              size: 18, color: _accent),
                          SizedBox(width: 10),
                          Text('New profile',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _accent)),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (nearby.isNotEmpty)
                        ...nearby.map((p) {
                          final sel = controller.selectedProfile?.id == p.id;
                          return GestureDetector(
                            onTap: () => select(p),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              decoration: BoxDecoration(
                                color: sel ? _accentSoft : _canvas,
                                borderRadius: BorderRadius.circular(14),
                                border: sel
                                    ? Border.all(color: _accent, width: 1.5)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      size: 15, color: _accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: sel
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: sel ? _accent : _ink,
                                      ),
                                    ),
                                  ),
                                  if (sel)
                                    const Icon(Icons.check_circle_rounded,
                                        color: _accent, size: 20),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (nearby.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            searchCtrl.text.trim().isEmpty
                                ? 'No profiles within '
                                    '${AttemptDraftController.kProfileFilterFt.toInt()} ft. '
                                    'Create one above.'
                                : 'No nearby profiles match '
                                    '"${searchCtrl.text.trim()}"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _inkSubtle, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _createProfile() async {
    final created = await showCreateProfileDialog(context);
    if (created != null && mounted) {
      controller.setSelectedProfile(created, ref: ref);
      controller.showSnack(context, 'Profile "${created.name}" created');
    }
  }

  void _showServedToPicker(BuildContext context) {
    HapticFeedback.lightImpact();

    void select(String value) {
      HapticFeedback.selectionClick();
      controller.setServedTo(value);
      Navigator.pop(context);
    }

    final servedToOptions = controller.servedToChoices(ref);

    Future<void> createCustom() async {
      final nameCtrl = TextEditingController();
      var gender = 'male';
      final result = await showDialog<({String name, String gender})>(
        context: context,
        useRootNavigator: true,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (dialogCtx, setDialog) => AlertDialog(
            backgroundColor: _surface,
            title: const Text('New name',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [TitleCaseInputFormatter()],
                  style: const TextStyle(color: _ink),
                  decoration: const InputDecoration(hintText: 'Full name'),
                ),
                const SizedBox(height: 14),
                const Text('Gender',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _inkMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const [
                      ('male', 'Male'),
                      ('female', 'Female'),
                      ('other', 'Other'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: gender == option.$1,
                        onSelected: (_) =>
                            setDialog(() => gender = option.$1),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(dialogCtx, (name: name, gender: gender));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (result != null && result.name.isNotEmpty) {
        await controller.addCustomServedToName(
          result.name,
          gender: result.gender,
        );
        select(result.name);
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        var query = '';
        var filter = 'all';
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final genders = LocalStorage.getServedToGenders();
            String groupOf(String name) {
              const known = {
                'John Doe': 'male',
                'Jane Doe': 'female',
              };
              final savedGender = known[name] ?? genders[name];
              if (savedGender == 'male' || savedGender == 'female') {
                return savedGender!;
              }
              return 'saved';
            }

            bool matches(String name) {
              final q = query.trim().toLowerCase();
              if (q.isNotEmpty && !name.toLowerCase().contains(q)) {
                return false;
              }
              if (filter == 'all') return true;
              return groupOf(name) == filter;
            }

            final quick = [
              for (final name in const ['Same as Profile', 'Posted to Door'])
                if (filter == 'all' && matches(name)) name,
            ];
            final people = [
              for (final name in servedToOptions)
                if (name != 'Same as Profile' &&
                    name != 'Posted to Door' &&
                    matches(name))
                  name,
            ];
            final male = [
              for (final name in people)
                if (groupOf(name) == 'male') name,
            ];
            final female = [
              for (final name in people)
                if (groupOf(name) == 'female') name,
            ];
            final saved = [
              for (final name in people)
                if (groupOf(name) != 'male' && groupOf(name) != 'female') name,
            ];

            Widget section(String title, List<String> names) {
              if (names.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _inkMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final name in names)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(name,
                          style: const TextStyle(color: _ink, fontSize: 15)),
                      onTap: () => select(name),
                    ),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _separator,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Served to',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        onChanged: (v) => setSheet(() => query = v),
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Search names',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF2F4F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final option in const [
                            ('all', 'All'),
                            ('male', 'Male'),
                            ('female', 'Female'),
                            ('saved', 'Saved'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(option.$2),
                                selected: filter == option.$1,
                                onSelected: (_) =>
                                    setSheet(() => filter = option.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          if (query.trim().isEmpty && filter == 'all')
                            ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading:
                                  const Icon(Icons.add_rounded, color: _accent),
                              title: const Text('New name',
                                  style: TextStyle(
                                      color: _accent,
                                      fontWeight: FontWeight.w600)),
                              onTap: createCustom,
                            ),
                          section('Quick', quick),
                          section('Male', male),
                          section('Female', female),
                          section('Saved names', saved),
                          if (quick.isEmpty && people.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No names match.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _inkSubtle, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNetworkCacheBanner() {
    final frozen = controller.locationFrozenFromCache;
    final title = frozen
        ? 'Location & time locked from cache'
        : 'Poor network — auto-caching attempt';
    final body = frozen
        ? 'Upload will use the cached geotag and capture time from when signal was bad — not your current GPS.'
        : 'Inputs are snapshotted every few seconds. Location/time will lock to the last known fix while signal stays poor.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x26F59E0B),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            frozen
                ? Icons.lock_clock
                : Icons.signal_cellular_connected_no_internet_4_bar,
            color: const Color(0xFFFBBF24),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFDE68A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFFDE68A),
                    height: 1.35,
                  ),
                ),
                if (frozen) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      final unlock = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: _surface,
                          title: const Text('Refresh location?',
                              style: TextStyle(color: _ink)),
                          content: const Text(
                            'This replaces the cached location/time with a new GPS fix. '
                            'Only do this if the cached geotag is wrong.',
                            style: TextStyle(color: _inkMuted),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Keep cached'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Refresh GPS'),
                            ),
                          ],
                        ),
                      );
                      if (unlock == true && mounted) {
                        controller.unlockLocationFromCache();
                        unawaited(controller.fetchLocation(context, ref));
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFBBF24),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Unlock & refresh GPS',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared atoms ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );

  Widget _sectionLabel(String label, IconData icon,
      {bool required = false, bool optional = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _inkMuted,
            letterSpacing: 0.1,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 6),
          const Text('*',
              style: TextStyle(
                  color: _errorRed, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
        if (optional)
          const Text(
            '  optional',
            style: TextStyle(fontSize: 11, color: _inkSubtle),
          ),
      ],
    );
  }

  Widget _fieldCaption(String label, {bool optional = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _inkSubtle,
          ),
        ),
        if (optional)
          const Text(
            '  optional',
            style: TextStyle(fontSize: 11, color: _inkSubtle),
          ),
      ],
    );
  }

  Widget _lockedRow(String title, {String? subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: _inkMuted)),
                ],
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded, size: 16, color: _accent),
        ],
      ),
    );
  }

  Widget _selectRow({String? value, required String placeholder}) {
    final has = value != null && value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: has ? _accentSoft : _canvas,
        borderRadius: BorderRadius.circular(12),
        border: has ? Border.all(color: _accent, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              has ? value : placeholder,
              style: TextStyle(
                fontSize: 14,
                fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                color: has ? _accent : _inkSubtle,
              ),
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: has ? _accent : _inkSubtle, size: 20),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required bool filled,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: filled ? _accent : _elevated,
        borderRadius: BorderRadius.circular(14),
        border: filled ? null : Border.all(color: _separator),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: filled ? Colors.white : _inkMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool voice = false,
    VoiceFillMode voiceMode = VoiceFillMode.replace,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 15, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkSubtle, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: _inkSubtle),
        suffixIcon: voice
            ? VoiceMicButton(controller: controller, mode: voiceMode)
            : null,
        filled: true,
        fillColor: _canvas,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _errorRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: _errorRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(fontSize: 13, color: _errorRed)),
            ),
          ],
        ),
      );

  Widget _shimmer({required double height}) => Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(12),
        ),
      );
}


class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
