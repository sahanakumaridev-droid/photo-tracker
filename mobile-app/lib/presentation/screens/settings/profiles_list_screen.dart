import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/create_profile_dialog.dart';

class ProfilesListScreen extends ConsumerStatefulWidget {
  const ProfilesListScreen({super.key});

  @override
  ConsumerState<ProfilesListScreen> createState() =>
      _ProfilesListScreenState();
}

class _ProfilesListScreenState extends ConsumerState<ProfilesListScreen> {
  // ── Search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Profile creation uses the shared dialog (same as upload & map-tap flows).
  // The list is rebuilt automatically via the watched profilesProvider.
  Future<void> _openCreateProfile() async {
    final created = await showCreateProfileDialog(context);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile "${created.name}" created')),
      );
    }
  }

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _grayBg   = Color(0xFFF8FAFC);
  static const Color _grayText = Color(0xFF6B7280);
  static const Color _graySubtle = Color(0xFF94A3B8);
  static const Color _accent   = Color(0xFF7C3AED);
  static const Color _border   = Color(0xFFE2E8F0);

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _svcColor(String serviceType) => categoryOf(serviceType).color;

  /// Find the most recent photo for [profile] and return its coordinates.
  /// Returns null if the profile has no photos.
  ({double lat, double lng})? _profileCoords(
    ProfileModel profile,
    List<PhotoModel> photos,
  ) {
    final profilePhotos = _profilePhotos(profile, photos);
    if (profilePhotos.isEmpty) return null;
    final latest = profilePhotos.first;
    return (lat: latest.latitude, lng: latest.longitude);
  }

  /// Get all photos for [profile], sorted newest first.
  List<PhotoModel> _profilePhotos(
    ProfileModel profile,
    List<PhotoModel> photos,
  ) {
    final list = photos.where((ph) =>
        ph.profileId == profile.id ||
        (ph.profiles?.any((p) => p.id == profile.id) ?? false),
    ).toList()
      ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return list;
  }

  /// Full URL for an image path.
  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  /// Format distance for display.
  String _formatDistance(double km) {
    if (km < 1.0) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  /// Sort profiles by distance from [userLat]/[userLng].
  /// Profiles with no photos go to the bottom.
  List<ProfileModel> _sortByDistance(
    List<ProfileModel> profiles,
    List<PhotoModel> photos,
    double userLat,
    double userLng,
  ) {
    final withDist = profiles.map((p) {
      final coords = _profileCoords(p, photos);
      final dist = coords == null
          ? double.infinity
          : LocationService.calculateDistance(
              userLat, userLng, coords.lat, coords.lng);
      return (profile: p, dist: dist);
    }).toList()
      ..sort((a, b) => a.dist.compareTo(b.dist));

    return withDist.map((e) => e.profile).toList();
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final photosAsync   = ref.watch(photosProvider);
    final locationAsync = ref.watch(currentLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_searchQuery.isEmpty ? 'Profiles' : 'Search results'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _grayText,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(photosProvider);
              ref.invalidate(currentLocationProvider);
            },
          ),
        ],
      ),
      backgroundColor: _grayBg,
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64,
                  color: Colors.red.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('Error loading profiles: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(profilesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (profiles) {
          if (profiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_outlined, size: 64,
                      color: _graySubtle),
                  const SizedBox(height: 16),
                  Text('No Profiles Yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _grayText, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Create your first profile to get started',
                    style: TextStyle(color: _graySubtle, fontSize: 14)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _openCreateProfile,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Profile'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12)),
                  ),
                ],
              ),
            );
          }

          // ── Sort by distance when GPS + photos are available ──────────
          final userPos  = locationAsync.valueOrNull;
          final photos   = photosAsync.valueOrNull ?? <PhotoModel>[];
          final sorted   = (userPos != null)
              ? _sortByDistance(
                  profiles, photos, userPos.latitude, userPos.longitude)
              : profiles;

          // ── Apply search filter ───────────────────────────────────────
          final filtered = _searchQuery.isEmpty
              ? sorted
              : sorted.where((p) =>
                  p.name.toLowerCase().contains(_searchQuery) ||
                  p.serviceType.toLowerCase().contains(_searchQuery) ||
                  (p.note?.toLowerCase().contains(_searchQuery) ?? false),
                ).toList();

          // ── Distance label per profile ────────────────────────────────
          final distMap = <int, double>{};
          if (userPos != null) {
            for (final p in profiles) {
              final coords = _profileCoords(p, photos);
              if (coords != null) {
                distMap[p.id] = LocationService.calculateDistance(
                  userPos.latitude, userPos.longitude,
                  coords.lat, coords.lng,
                );
              }
            }
          }

          return Column(
            children: [
              // ── Search bar ────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase()),
                  style: const TextStyle(fontSize: 14, color: _grayText),
                  decoration: InputDecoration(
                    hintText: 'Search by name, type or note…',
                    hintStyle:
                        const TextStyle(color: _graySubtle, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: _graySubtle),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Icon(Icons.close_rounded,
                                size: 18, color: _graySubtle),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // ── Location status banner ──────────────────────────────
              if (userPos == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: const Color(0xFFFFF7ED),
                  child: Row(children: [
                    const Icon(Icons.near_me_outlined,
                        size: 16, color: Color(0xFFEA580C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locationAsync.isLoading
                            ? 'Getting your location…'
                            : 'Location unavailable — showing default order',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFEA580C)),
                      ),
                    ),
                  ]),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: const Color(0xFFECFDF5),
                  child: Row(children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Text(
                      'Sorted by distance from your location'
                      ' · ±${userPos.accuracy.toStringAsFixed(0)}m',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ]),
                ),

              // ── Profile list ──────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.manage_search_rounded,
                                size: 52, color: _graySubtle),
                            const SizedBox(height: 12),
                            Text(
                              'No profiles match "$_searchQuery"',
                              style: const TextStyle(
                                  fontSize: 14, color: _graySubtle),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Text('Clear search'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final profile  = filtered[index];
                          final dist     = distMap[profile.id];
                          final pPhotos  = _profilePhotos(profile, photos);
                          final photoUrl = pPhotos.isNotEmpty
                              ? _fullUrl(pPhotos.first.imageUrl)
                              : null;
                          return _buildProfileCard(
                              context, profile, dist, photoUrl);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateProfile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Profile'),
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    ProfileModel profile,
    double? distKm,
    String? photoUrl,
  ) {
    final svcColor = _svcColor(profile.serviceType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/profiles-management', extra: profile),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── Photo thumbnail or colour dot fallback ──────────────
                _ProfileAvatar(
                  photoUrl: photoUrl,
                  svcColor: svcColor,
                  name: profile.name,
                ),
                const SizedBox(width: 14),

                // ── Name / type / note / distance ───────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _grayText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        categoryLabel(profile.serviceType).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: svcColor,
                        ),
                      ),
                      if (profile.note != null &&
                          profile.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _graySubtle,
                          ),
                        ),
                      ],
                      // ── Distance badge ──────────────────────────────
                      if (distKm != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.navigation_rounded,
                                size: 12, color: _accent),
                            const SizedBox(width: 4),
                            Text(
                              _formatDistance(distKm),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 5),
                        const Text(
                          'No photos yet',
                          style: TextStyle(
                            fontSize: 11,
                            color: _graySubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Icon(Icons.chevron_right_rounded,
                    size: 24, color: _border),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Circular avatar — shows the profile's latest photo, falls back to colour dot
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.photoUrl,
    required this.svcColor,
    required this.name,
  });

  final String? photoUrl;
  final Color   svcColor;
  final String  name;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallback(),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: svcColor.withValues(alpha: 0.15),
          border: Border.all(color: svcColor.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: svcColor,
            ),
          ),
        ),
      );
}
