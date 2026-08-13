import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// "More" hub — quick access to the secondary feature areas (Earnings,
/// Schedule, Archive, Profiles) plus a link into full Settings. Lives in the
/// bottom nav's former Settings slot so the primary tabs stay uncluttered as
/// new feature screens are added.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _muted = Color(0xFF94A3B8);
  static const Color _bg = Color(0xFF0F1219);
  static const Color _card = Color(0xFF1C222E);
  static const Color _hair = Color(0xFF2A3340);

  static const List<BoxShadow> _softShadow = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const _tiles = [
    (
      'Schedule',
      'ASAP, Next Day, Standard & Special queues',
      CupertinoIcons.calendar,
      Color(0xFF4A90E2),
      '/schedule',
    ),
    (
      'Archive',
      'Active, completed & archived jobs',
      CupertinoIcons.archivebox,
      Color(0xFFF59E0B),
      '/archive',
    ),
    (
      'Profiles',
      'Manage your saved profiles',
      CupertinoIcons.folder,
      Color(0xFF0EA5E9),
      '/profiles-list',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('More',
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: _tiles.map((t) => _tile(context, t)).toList(),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _softShadow,
            ),
            child: _row(
              context,
              icon: CupertinoIcons.gear,
              title: 'Settings',
              subtitle: 'Account, preferences & support',
              route: '/settings',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
      BuildContext context,
      (String, String, IconData, Color, String) item) {
    final (title, subtitle, icon, color, route) = item;
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(route);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink)),
              const SizedBox(height: 4),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: _muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push(route);
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
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: _muted)),
                  ],
                ),
              ),
              const Icon(CupertinoIcons.chevron_right,
                  size: 22, color: _hair),
            ]),
          ),
        ),
      );
}
