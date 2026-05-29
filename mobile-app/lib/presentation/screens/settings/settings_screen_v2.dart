import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class SettingsScreenV2 extends ConsumerWidget {
  const SettingsScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeState = ref.watch(themeProvider);

    const grayBg = Color(0xFFF8FAFC);
    const grayText = Color(0xFF475569);
    const graySubtle = Color(0xFF94A3B8);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: grayText,
      ),
      backgroundColor: grayBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: const Icon(
                      Icons.person_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.email ?? 'User Account',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: grayText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Active',
                          style: TextStyle(fontSize: 13, color: graySubtle),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Permissions ───────────────────────────────────────────
            _buildSection(
              context,
              title: 'Permissions',
              children: [
                _buildSettingItem(
                  context,
                  icon: Icons.camera_alt_outlined,
                  title: 'Camera & Location',
                  subtitle: 'Tap to manage in system Settings',
                  onTap: openAppSettings,
                ),
              ],
            ),

            // Profiles Section
            _buildSection(
              context,
              title: 'Profiles',
              children: [
                _buildSettingItem(
                  context,
                  icon: Icons.folder_outlined,
                  title: 'Manage Profiles',
                  subtitle: 'View and manage your profiles',
                  onTap: () => context.push('/profiles-list'),
                ),
              ],
            ),

            // Account Section
            _buildSection(
              context,
              title: 'Account',
              children: [
                _buildSettingItem(
                  context,
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: authState.email ?? 'Not set',
                  onTap: () {},
                ),
                _buildSettingItem(
                  context,
                  icon: Icons.lock_outline,
                  title: 'Password',
                  subtitle: 'Change your password',
                  onTap: () {},
                ),
              ],
            ),

            // Preferences Section
            _buildSection(
              context,
              title: 'Preferences',
              children: [
                _buildSwitchItem(
                  context,
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  value: themeState.mode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(themeProvider.notifier).toggleTheme(),
                ),
                _buildColorPickerItem(
                  context,
                  icon: Icons.palette_outlined,
                  title: 'Accent Color',
                  currentColor: themeState.accentColor,
                  onColorSelected: (color) =>
                      ref.read(themeProvider.notifier).setAccentColor(color),
                ),
              ],
            ),

            // App Section
            _buildSection(
              context,
              title: 'App',
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 22, color: Color(0xFF475569)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Version', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF475569))),
                            SizedBox(height: 2),
                            Text('Current app version', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEEEFD),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'v${AppConfig.appVersion}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5B5BD6)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0), indent: 56),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.engineering_rounded, size: 22, color: Color(0xFF475569)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Environment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF475569))),
                            SizedBox(height: 2),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'QA',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0), indent: 56),
                _buildSettingItem(
                  context,
                  icon: Icons.storage_outlined,
                  title: 'Cache',
                  subtitle: 'Clear app cache',
                  onTap: () => _showClearCacheDialog(context),
                ),
              ],
            ),

            // Support Section
            _buildSection(
              context,
              title: 'Support',
              children: [
                _buildSettingItem(
                  context,
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'Get help with the app',
                  onTap: () {},
                ),
                _buildSettingItem(
                  context,
                  icon: Icons.description_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'Read our privacy policy',
                  onTap: () {},
                ),
                _buildSettingItem(
                  context,
                  icon: Icons.gavel_outlined,
                  title: 'Terms of Service',
                  subtitle: 'Read our terms',
                  onTap: () {},
                ),
              ],
            ),

            // Logout
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showLogoutDialog(context, ref),
                  icon: const Icon(Icons.logout_outlined),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Column(
            children: List.generate(
              children.length,
              (index) => Column(
                children: [
                  children[index],
                  if (index < children.length - 1)
                    const Divider(
                      height: 1,
                      color: Color(0xFFE2E8F0),
                      indent: 56,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );

  Widget _buildSettingItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: const Color(0xFF475569),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_outlined,
                size: 20,
                color: Color(0xFFE2E8F0),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildSwitchItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: const Color(0xFF475569),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );

  Widget _buildColorPickerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color currentColor,
    required Function(String) onColorSelected,
  }) {
    final colors = [
      ('indigo', const Color(0xFF6366f1)),
      ('purple', const Color(0xFF8b5cf6)),
      ('blue', const Color(0xFF3b82f6)),
      ('green', const Color(0xFF10b981)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: const Color(0xFF475569),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF475569),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: onColorSelected,
            itemBuilder: (context) => colors
                .map(
                  (item) => PopupMenuItem(
                    value: item.$1,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: item.$2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(item.$1.toUpperCase()),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('Are you sure you want to clear the app cache?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
