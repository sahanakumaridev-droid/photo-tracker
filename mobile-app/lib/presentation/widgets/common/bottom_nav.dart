import 'dart:ui';

import 'package:flutter/material.dart';

class BottomNav extends StatefulWidget {

  const BottomNav({
    required this.currentIndex, required this.onTap, super.key,
  });
  final int currentIndex;
  final Function(int) onTap;

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark
                      ? const Color(0xFF2d2640)
                      : const Color(0xFFffffff))
                  .withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF3d3650).withValues(alpha: 0.5)
                      : const Color(0xFFe2e8f0).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    5,
                    (index) => _buildNavItem(
                      index: index,
                      isActive: widget.currentIndex == index,
                      primaryColor: primaryColor,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required bool isActive,
    required Color primaryColor,
    required bool isDark,
  }) {
    final items = [
      {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'Home'},
      {
        'icon': Icons.map_outlined,
        'activeIcon': Icons.map,
        'label': 'Map'
      },
      {
        'icon': Icons.add_a_photo_outlined,
        'activeIcon': Icons.add_a_photo,
        'label': 'Upload'
      },
      {
        'icon': Icons.history_outlined,
        'activeIcon': Icons.history,
        'label': 'Log'
      },
      {
        'icon': Icons.settings_outlined,
        'activeIcon': Icons.settings,
        'label': 'Settings'
      },
    ];

    final item = items[index];

    return GestureDetector(
      onTap: () {
        widget.onTap(index);
        _animationController.forward().then((_) {
          _animationController.reverse();
        });
      },
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) => Transform.scale(
            scale: isActive ? 1.0 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isActive
                    ? Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? item['activeIcon']! as IconData
                        : item['icon']! as IconData,
                    color: isActive ? primaryColor : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['label']! as String,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? primaryColor : Colors.grey,
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
