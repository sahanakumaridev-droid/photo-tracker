import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';

class HomeScreenV2 extends ConsumerStatefulWidget {
  const HomeScreenV2({super.key});

  @override
  ConsumerState<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends ConsumerState<HomeScreenV2>
    with SingleTickerProviderStateMixin {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _canvas = Color(0xFFF2F4F7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0D1117);
  static const Color _inkMuted = Color(0xFF4B5563);
  static const Color _inkSubtle = Color(0xFF9CA3AF);
  static const Color _separator = Color(0xFFE5E7EB);
  static const Color _accent = Color(0xFF5B5BD6);
  static const Color _accentSoft = Color(0xFFEEEEFD);
  static const Color _rushRed = Color(0xFFDC2626);
  static const Color _standardGreen = Color(0xFF059669);
  static const Color _airportBlue = Color(0xFF0284C7);

  // ── State ─────────────────────────────────────────────────────────────────
  String _selectedProfileId = 'all';
  bool _isGridView = true;

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _svcColor(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush': return _rushRed;
      case 'airport': return _airportBlue;
      default: return _standardGreen;
    }
  }

  String _svcLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'rush': return 'Rush';
      case 'airport': return 'Airport';
      default: return 'Standard';
    }
  }

  String _formatTs(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(ts).toLocal());
    } catch (_) { return ts; }
  }

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  int _thisMonthCount(List<PhotoModel> photos) {
    final now = DateTime.now();
    return photos.where((p) {
      if (p.timestamp == null) return false;
      try {
        final d = DateTime.parse(p.timestamp!);
        return d.year == now.year && d.month == now.month;
      } catch (_) { return false; }
    }).length;
  }

  List<PhotoModel> _filtered(List<PhotoModel> photos) {
    if (_selectedProfileId == 'all') return photos;
    return photos.where((p) {
      if (p.profileId?.toString() == _selectedProfileId) return true;
      return p.profiles?.any((pr) => pr.id.toString() == _selectedProfileId) ?? false;
    }).toList();
  }

  /// Extract first name from email: "sahana@gmail.com" → "Sahana"
  String _firstName(String? email) {
    if (email == null || email.isEmpty) return 'there';
    final local = email.split('@').first;
    final name = local.replaceAll(RegExp(r'[._\-0-9]'), ' ').trim();
    if (name.isEmpty) return 'there';
    return name.split(' ').first.capitalize();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final profilesAsync = ref.watch(profilesProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: _canvas,
      body: RefreshIndicator(
        color: _accent,
        backgroundColor: _surface,
        onRefresh: () async {
          HapticFeedback.lightImpact();
          ref.invalidate(photosProvider);
          ref.invalidate(profilesProvider);
        },
        child: CustomScrollView(
          slivers: [
            _buildSliverHeader(authState),
            photosAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                ),
              ),
              error: (err, _) => SliverFillRemaining(child: _buildError(err)),
              data: (photos) => profilesAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(child: _buildError(err)),
                data: (profiles) => _buildContent(photos, profiles),
              ),
            ),
          ],
        ),
      ),

    );
  }

  // ── Sliver header ─────────────────────────────────────────────────────────
  Widget _buildSliverHeader(AuthState authState) => SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      floating: false,
      elevation: 0,
      toolbarHeight: 100,
      backgroundColor: const Color(0xFF4F46E5),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: _buildHeaderBackground(authState),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _separator),
      ),
    );

  Widget _buildHeaderBackground(AuthState authState) {
    final firstName = _firstName(authState.email);
    final greeting = _greeting();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Left: logo + greeting ──────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              Positioned(
                                bottom: 5,
                                right: 5,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34D399),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Geo',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              TextSpan(
                                text: 'Tag',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFA5B4FC),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$greeting, $firstName 👋',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Right: action buttons ──────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerBtn(
                    icon: Icons.map_rounded,
                    tooltip: 'Map View',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/map');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );

  // ── Content ───────────────────────────────────────────────────────────────
  Widget _buildContent(List<PhotoModel> photos, List<ProfileModel> profiles) {
    final filtered = _filtered(photos);
    return SliverList(
      delegate: SliverChildListDelegate([
        _buildStatCards(photos, profiles),
        _buildProfileFilter(photos, profiles),
        _buildSectionHeader(filtered.length),
        if (filtered.isEmpty)
          _buildEmptyState()
        else if (_isGridView)
          _buildPhotoGrid(filtered)
        else
          _buildPhotoList(filtered),
        const SizedBox(height: 100),
      ]),
    );
  }

  // ── Stat cards (2 × 2 grid) ───────────────────────────────────────────────
  static const List<List<Color>> _statGradients = [
    [Color(0xFF4F46E5), Color(0xFF7C3AED)], // indigo → purple
    [Color(0xFF059669), Color(0xFF0D9488)], // green → teal
    [Color(0xFF0284C7), Color(0xFF0EA5E9)], // blue
    [Color(0xFFDC2626), Color(0xFFEA580C)], // red → orange
  ];

  Widget _buildStatCards(
      List<PhotoModel> photos, List<ProfileModel> profiles) {
    final stats = [
      (
        label: 'Total Photos',
        value: '${photos.length}',
        icon: Icons.photo_library_rounded,
        gradIdx: 0,
      ),
      (
        label: 'Profiles',
        value: '${profiles.length}',
        icon: Icons.people_rounded,
        gradIdx: 1,
      ),
      (
        label: 'This Month',
        value: '${_thisMonthCount(photos)}',
        icon: Icons.calendar_month_rounded,
        gradIdx: 2,
      ),
      (
        label: 'Rush Jobs',
        value: '${photos.where((p) => p.serviceType == 'rush').length}',
        icon: Icons.bolt_rounded,
        gradIdx: 3,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statCard(stats[0])),
              const SizedBox(width: 12),
              Expanded(child: _statCard(stats[1])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard(stats[2])),
              const SizedBox(width: 12),
              Expanded(child: _statCard(stats[3])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(
      ({String label, String value, IconData icon, int gradIdx}) s) {
    final grad = _statGradients[s.gradIdx];
    return Container(
      height: 110,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: grad[0].withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Decorative circle top-right
            Positioned(
              top: -16,
              right: -16,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Content — use Column with mainAxisAlignment.spaceBetween
            // so no Spacer() is needed (Spacer needs unbounded height)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(s.icon, size: 17, color: Colors.white),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.value,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile filter (dropdown — scales to any number of profiles) ────────
  Widget _buildProfileFilter(
      List<PhotoModel> photos, List<ProfileModel> profiles) {
    // Build the items list: "All" + each profile
    final items = <({String id, String name, int count, String? svcType})>[
      (id: 'all', name: 'All Photos', count: photos.length, svcType: null),
      ...profiles.map((p) {
        final count = photos
            .where((ph) =>
                ph.profileId == p.id ||
                (ph.profiles?.any((pr) => pr.id == p.id) ?? false))
            .length;
        return (
          id: p.id.toString(),
          name: p.name,
          count: count,
          svcType: p.serviceType,
        );
      }),
    ];

    final selected = items.firstWhere(
      (i) => i.id == _selectedProfileId,
      orElse: () => items.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Dropdown button
          Expanded(
            child: GestureDetector(
              onTap: () => _showProfilePicker(items),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Color dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: selected.id == 'all'
                            ? _accent
                            : _svcColor(selected.svcType),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selected.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _canvas,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${selected.count}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _inkSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Manage button
          GestureDetector(
            onTap: () => context.push('/settings'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Manage',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePicker(
    List<({String id, String name, int count, String? svcType})> items,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
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
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Filter by Profile',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${items.length - 1} profiles',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _inkSubtle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final sel = _selectedProfileId == item.id;
                  final color =
                      item.id == 'all' ? _accent : _svcColor(item.svcType);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedProfileId = item.id);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? color.withValues(alpha: 0.08)
                            : _canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: sel
                            ? Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: item.id == 'all'
                                  ? Icon(
                                      Icons.photo_library_rounded,
                                      size: 16,
                                      color: color,
                                    )
                                  : Text(
                                      item.name[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: sel ? color : _ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? color.withValues(alpha: 0.15)
                                  : _separator,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.count}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel ? color : _inkMuted,
                              ),
                            ),
                          ),
                          if (sel) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: color,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────
  Widget _buildSectionHeader(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(
          children: [
            const Text(
              'Photos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _separator,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _inkMuted,
                ),
              ),
            ),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _separator),
              ),
              child: Row(
                children: [
                  _toggleBtn(Icons.grid_view_rounded, _isGridView,
                      () => setState(() => _isGridView = true)),
                  _toggleBtn(Icons.view_list_rounded, !_isGridView,
                      () => setState(() => _isGridView = false)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _toggleBtn(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: active ? _accent : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 16, color: active ? Colors.white : _inkSubtle),
        ),
      );

  // ── Photo grid ────────────────────────────────────────────────────────────
  Widget _buildPhotoGrid(List<PhotoModel> photos) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: photos.length,
          itemBuilder: (_, i) => _gridCard(photos[i]),
        ),
      );

  Widget _gridCard(PhotoModel photo) {
    final svcColor = _svcColor(photo.serviceType);
    final url = _fullUrl(photo.imageUrl);
    return GestureDetector(
      onTap: () => context.push('/photo/${photo.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : Container(color: _canvas,
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent))),
                      errorBuilder: (_, __, ___) => Container(
                        color: _canvas,
                        child: const Center(child: Icon(Icons.broken_image_outlined, color: _inkSubtle, size: 28)),
                      ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: svcColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _svcLabel(photo.serviceType),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.profileName ?? 'Unknown',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 11, color: _inkSubtle),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          photo.zipCode ?? '${photo.latitude.toStringAsFixed(2)}, ${photo.longitude.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: _inkSubtle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (photo.timestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(_formatTs(photo.timestamp), style: const TextStyle(fontSize: 10, color: _inkSubtle)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Photo list ────────────────────────────────────────────────────────────
  Widget _buildPhotoList(List<PhotoModel> photos) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: photos.length,
          itemBuilder: (_, i) => _listCard(photos[i]),
        ),
      );

  Widget _listCard(PhotoModel photo) {
    final svcColor = _svcColor(photo.serviceType);
    final url = _fullUrl(photo.imageUrl);
    return GestureDetector(
      onTap: () => context.push('/photo/${photo.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
              child: SizedBox(
                width: 88,
                height: 88,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : Container(color: _canvas,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent))),
                  errorBuilder: (_, __, ___) => Container(
                    color: _canvas,
                    child: const Center(child: Icon(Icons.broken_image_outlined, color: _inkSubtle, size: 24)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            photo.profileName ?? 'Unknown',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: svcColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _svcLabel(photo.serviceType),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: svcColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 12, color: _inkSubtle),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            photo.zipCode != null ? 'ZIP ${photo.zipCode}' : '${photo.latitude.toStringAsFixed(4)}, ${photo.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 12, color: _inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (photo.timestamp != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 12, color: _inkSubtle),
                          const SizedBox(width: 3),
                          Text(_formatTs(photo.timestamp), style: const TextStyle(fontSize: 12, color: _inkMuted)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded, color: _inkSubtle, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: _accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.photo_library_outlined, size: 36, color: _accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'No photos yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -0.3),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedProfileId == 'all'
                  ? 'Upload your first photo to get started'
                  : 'No photos for this profile',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _inkSubtle),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/upload'),
              icon: const Icon(Icons.add_a_photo_rounded, size: 18),
              label: const Text('Upload Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      );

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError(Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _rushRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded, size: 32, color: _rushRed),
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load photos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString().replaceAll('Exception: ', ''),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _inkSubtle),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ref.invalidate(photosProvider);
                  ref.invalidate(profilesProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
}
