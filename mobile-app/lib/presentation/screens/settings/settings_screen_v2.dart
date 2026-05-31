import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

/// Settings — clean consumer profile + preferences. Grouped white cards,
/// hairline borders, soft shadows, navy ink, royal-blue accent.
class SettingsScreenV2 extends ConsumerWidget {
  const SettingsScreenV2({super.key});

  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _green = Color(0xFF10B981);
  static const Color _red = Color(0xFFEF4444);
  static const Color _bg = Color(0xFFFAFAFA);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _hair = Color(0xFFE5E7EB);

  static const List<BoxShadow> _softShadow = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4)),
  ];

  String _displayName(String? email) {
    if (email == null || email.isEmpty) return 'Your Account';
    final local = email.split('@').first;
    final name = local.replaceAll(RegExp(r'[._\-0-9]'), ' ').trim();
    if (name.isEmpty) return email;
    return name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeState = ref.watch(themeProvider);
    final name = _displayName(authState.email);
    final initial = name.isEmpty ? 'A' : name[0].toUpperCase();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
        elevation: 0,
        backgroundColor: _card,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: _hair)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── Profile header ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _softShadow,
            ),
            child: Row(children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text(authState.email ?? 'Not signed in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.check_circle_rounded,
                            size: 12, color: _green),
                        SizedBox(width: 4),
                        Text('Active',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _green)),
                      ]),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          _section('Workspace', [
            _row(Icons.folder_copy_outlined, 'Manage Profiles',
                subtitle: 'View and organize your profiles',
                onTap: () => context.push('/profiles-list')),
            _row(Icons.camera_alt_outlined, 'Camera & Location',
                subtitle: 'Manage permissions in system Settings',
                onTap: openAppSettings),
          ]),

          _section('Account', [
            _row(Icons.email_outlined, 'Email',
                subtitle: authState.email ?? 'Not set', onTap: () {}),
            _row(Icons.lock_outline_rounded, 'Password',
                subtitle: 'Change your password', onTap: () {}),
          ]),

          _section('Preferences', [
            _switchRow(
              Icons.dark_mode_outlined,
              'Dark Mode',
              value: themeState.mode == ThemeMode.dark,
              onChanged: (_) {
                HapticFeedback.selectionClick();
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
            _colorRow(
              currentColor: themeState.accentColor,
              onSelected: (c) =>
                  ref.read(themeProvider.notifier).setAccentColor(c),
            ),
          ]),

          _section('Support', [
            _row(Icons.help_outline_rounded, 'Help & Support',
                subtitle: 'Get help with the app', onTap: () {}),
            _row(Icons.shield_outlined, 'Privacy Policy',
                subtitle: 'How we handle your data', onTap: () {}),
            _row(Icons.description_outlined, 'Terms of Service',
                subtitle: 'Read our terms', onTap: () {}),
          ]),

          _section('About', [
            _row(Icons.info_outline_rounded, 'Version',
                subtitle: 'GeoTag mobile',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('v${AppConfig.appVersion}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _purple)),
                ),
                onTap: () {}),
          ]),

          const SizedBox(height: 8),
          // ── Logout ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log Out',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                backgroundColor: _card,
                side: BorderSide(color: _red.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable bits ───────────────────────────────────────────────────────
  Widget _section(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(title.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.8)),
            ),
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _softShadow,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    rows[i],
                    if (i < rows.length - 1)
                      const Divider(
                          height: 1, color: _hair, indent: 60, endIndent: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _row(IconData icon, String title,
          {String? subtitle, Widget? trailing, required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: _ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: _muted)),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      size: 22, color: _hair),
            ]),
          ),
        ),
      );

  Widget _switchRow(IconData icon, String title,
          {required bool value, required ValueChanged<bool> onChanged}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: _ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _purple,
          ),
        ]),
      );

  Widget _colorRow(
      {required Color currentColor,
      required ValueChanged<String> onSelected}) {
    const colors = [
      ('purple', Color(0xFF7C3AED)),
      ('violet', Color(0xFF8B5CF6)),
      ('indigo', Color(0xFF6366F1)),
      ('black', Color(0xFF1F1F1F)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration:
              BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.palette_outlined, size: 19, color: _ink),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Accent Color',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: colors.map((c) {
            final selected = c.$2.toARGB32() == currentColor.toARGB32();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(c.$1);
              },
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c.$2,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: selected ? _ink : Colors.transparent, width: 2),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Log out?',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
        content: const Text(
            'You’ll need to sign in again to access your GeoTags.',
            style: TextStyle(color: _muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/onboarding');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}
