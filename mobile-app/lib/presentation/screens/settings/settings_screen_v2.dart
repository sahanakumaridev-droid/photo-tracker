import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import 'ai_assistant_sheet.dart';

// ── AI & automation preferences ──────────────────────────────────────────────
// Lightweight in-session toggles. Riverpod keeps these alive across navigation;
// swap the StateProviders for a persisted notifier once the AI endpoints ship.
final aiSmartSuggestionsProvider = StateProvider<bool>((ref) => true);
final aiAutoTagProvider = StateProvider<bool>((ref) => true);
final aiDataUsageProvider = StateProvider<bool>((ref) => false);

/// Settings — 2026 consumer redesign. AI-first: a featured GeoTag AI card and
/// an Automation group sit above the classic preference cards, with a dedicated
/// Privacy & Data section (data export + AI-training opt-in) reflecting current
/// US privacy expectations. Grouped cards, hairline borders, soft shadows.
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

  // Per-row icon accent palette — gives each row a distinct, legible tint
  // instead of a uniform gray block.
  static const Color _cBlue = Color(0xFF2563EB);
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cSlate = Color(0xFF475569);
  static const Color _cTeal = Color(0xFF0D9488);
  static const Color _cRose = Color(0xFFE11D48);
  static const Color _cIndigo = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeState = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final name = _displayName(authState.email);
    final initial = name.isEmpty ? 'A' : name[0].toUpperCase();
    final accent = themeState.accentColor;
    final smartSuggestions = ref.watch(aiSmartSuggestionsProvider);
    final autoTag = ref.watch(aiAutoTagProvider);
    final aiDataUsage = ref.watch(aiDataUsageProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          // ── Collapsing gradient hero ─────────────────────────────────────
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 232,
            backgroundColor: accent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final statusBar = MediaQuery.of(context).padding.top;
                final collapsed = kToolbarHeight + statusBar;
                final t = ((constraints.maxHeight - collapsed) /
                        (232 - collapsed))
                    .clamp(0.0, 1.0);
                return _hero(t, name, authState.email, initial, accent);
              },
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
          _section('AI & Automation', [
            _aiToggleRow(
              Icons.auto_awesome_rounded, 'Smart Suggestions', _purple,
              subtitle: 'Surface the next best job & route as you work',
              value: smartSuggestions,
              onChanged: (v) =>
                  ref.read(aiSmartSuggestionsProvider.notifier).state = v,
            ),
            _divider(),
            _aiToggleRow(
              Icons.sell_rounded, 'Auto-Tag Photos', _cTeal,
              subtitle: 'Detect location, category & captions on upload',
              value: autoTag,
              onChanged: (v) => ref.read(aiAutoTagProvider.notifier).state = v,
            ),
            _divider(),
            _row(Icons.chat_bubble_rounded, 'AI Assistant', _cIndigo,
                subtitle: 'Ask about jobs, earnings & schedule',
                onTap: () => showAiAssistantSheet(context)),
          ]),
          const SizedBox(height: 22),

          _section('Workspace', [
            _row(Icons.folder_rounded, 'Manage Profiles', accent,
                subtitle: 'View and organize your profiles',
                onTap: () => context.push('/profiles-list')),
            _row(Icons.camera_alt_rounded, 'Camera & Location', _cBlue,
                subtitle: 'Manage permissions in system Settings',
                onTap: openAppSettings),
          ]),
          const SizedBox(height: 22),

          // Enhancement features (F4/F8/F9/F10)
          _section('Jobs & Earnings', [
            _row(Icons.payments_rounded, 'Earnings', _green,
                subtitle: 'Today, week, bi-weekly & monthly payouts',
                onTap: () => context.push('/earnings')),
            _row(Icons.calendar_today_rounded, 'Schedule', _cAmber,
                subtitle: 'ASAP, Next Day, Standard & Special queues',
                onTap: () => context.push('/schedule')),
            _row(Icons.archive_rounded, 'Archive', _cSlate,
                subtitle: 'Search and review completed jobs',
                onTap: () => context.push('/archive')),
          ]),
          const SizedBox(height: 22),

          _section('Account & Security', [
            _row(Icons.email_rounded, 'Email', _cBlue,
                subtitle: authState.email ?? 'Not set', onTap: () {}),
            _row(Icons.lock_rounded, 'Password', _cRose,
                subtitle: 'Change your password', onTap: () {}),
            _row(Icons.fingerprint_rounded, 'Passkeys & 2FA', _cIndigo,
                subtitle: 'Sign in with Face ID — no password needed',
                trailing: _pill('SET UP', _cIndigo), onTap: () {}),
          ]),
          const SizedBox(height: 22),

          _section('Privacy & Data', [
            _row(Icons.tune_rounded, 'Data & Permissions', _cSlate,
                subtitle: 'Control what GeoTag can access',
                onTap: openAppSettings),
            _aiToggleRow(
              Icons.model_training_rounded, 'Improve AI with my data', _purple,
              subtitle: 'Share anonymized usage to train smarter models',
              value: aiDataUsage,
              onChanged: (v) =>
                  ref.read(aiDataUsageProvider.notifier).state = v,
            ),
            _divider(),
            _row(Icons.download_rounded, 'Export My Data', _cTeal,
                subtitle: 'Download your photos & job history',
                onTap: () {}),
            _row(Icons.shield_rounded, 'Privacy Policy', _cIndigo,
                subtitle: 'How we handle your data', onTap: () {}),
          ]),
          const SizedBox(height: 22),

          _section('Appearance', [
            _row(Icons.language_rounded, 'Language', _cIndigo,
                subtitle: _languageLabel(locale),
                onTap: () => _showLanguagePicker(context, ref, locale)),
          ]),
          const SizedBox(height: 22),

          _section('Support', [
            _row(Icons.help_rounded, 'Help & Support', _cTeal,
                subtitle: 'Get help with the app', onTap: () {}),
            _row(Icons.description_rounded, 'Terms of Service', _cSlate,
                subtitle: 'Read our terms', onTap: () {}),
          ]),
          const SizedBox(height: 22),

          _section('About', [
            _row(Icons.info_rounded, 'Version', _purple,
                subtitle: 'GeoTag mobile',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('v${AppConfig.appVersion}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _purple)),
                ),
                onTap: () {}),
          ]),

          const SizedBox(height: 12),
          // ── Logout ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log Out',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                backgroundColor: _card,
                side: BorderSide(color: _red.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text('GeoTag • v${AppConfig.appVersion}',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500)),
          ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Collapsing gradient hero ──────────────────────────────────────────────
  // [t] = 1.0 fully expanded, 0.0 fully collapsed. The title scales and the
  // profile block fades out as the user scrolls up.
  Widget _hero(
      double t, String name, String? email, String initial, Color accent) {
    final dark = Color.lerp(accent, Colors.black, 0.34)!;
    final fade = Curves.easeOut.transform(t);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, dark],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Decorative soft circles
          Positioned(
            top: -42,
            right: -28,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -56,
            left: -34,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    // Shrink with collapse so titleBox + padding never exceeds
                    // the pinned toolbar height (prevents RenderFlex overflow).
                    height: 34 + 16 * fade,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 20 + 8 * fade,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: Opacity(
                        opacity: fade,
                        // OverflowBox lets the profile lay out at its natural
                        // height (no RenderFlex overflow) while the ClipRect
                        // trims any excess as the bar collapses.
                        child: OverflowBox(
                          alignment: Alignment.bottomLeft,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: _heroProfile(name, email, initial),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroProfile(String name, String? email, String initial) {
    return Row(children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3)),
            const SizedBox(height: 3),
            Text(email ?? 'Not signed in',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text('Active',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  // ── Language ─────────────────────────────────────────────────────────────
  String _languageLabel(Locale? locale) {
    if (locale == null) return LocaleNotifier.languages['system']!;
    return LocaleNotifier.languages[locale.languageCode] ?? locale.languageCode;
  }

  void _showLanguagePicker(
      BuildContext context, WidgetRef ref, Locale? current) {
    final currentCode = current?.languageCode ?? 'system';
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Language',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
              ),
            ),
            for (final entry in LocaleNotifier.languages.entries)
              ListTile(
                title: Text(entry.value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
                trailing: entry.key == currentCode
                    ? const Icon(Icons.check_rounded, color: _purple)
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(localeProvider.notifier).setLocale(entry.key);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
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
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF0F0F3)),
                boxShadow: _softShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    rows[i],
                    if (i < rows.length - 1)
                      const Divider(
                          height: 1, color: _hair, indent: 62, endIndent: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _row(IconData icon, String title, Color accent,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: accent),
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

  // ── AI bits ───────────────────────────────────────────────────────────────
  Widget _divider() =>
      const Divider(height: 1, color: _hair, indent: 62, endIndent: 16);

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.4)),
      );

  Widget _aiToggleRow(IconData icon, String title, Color accent,
          {String? subtitle,
          String? badge,
          required bool value,
          required ValueChanged<bool> onChanged}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink)),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    _pill(badge, accent),
                  ],
                ]),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeThumbColor: accent,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ]),
      );

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
