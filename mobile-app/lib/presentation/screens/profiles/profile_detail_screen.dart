import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/category.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/photo_preview_gallery.dart';

class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({required this.profileId, super.key});

  final int profileId;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _ink    = Color(0xFF0F0F0F);
  static const Color _muted  = Color(0xFF6B7280);
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _soft   = Color(0xFFEDE9FE);
  static const Color _bg     = Color(0xFFF7F5FF);
  static const Color _card   = Color(0xFFFFFFFF);
  static const Color _hair   = Color(0xFFE5E7EB);

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  String _shortDate(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return '';
    }
  }

  // Group photos by their address, newest first within each group.
  Map<String, List<PhotoModel>> _groupByAddress(List<PhotoModel> photos) {
    final sorted = List<PhotoModel>.from(photos)
      ..sort((a, b) =>
          (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    final map = <String, List<PhotoModel>>{};
    for (final p in sorted) {
      final addr = (p.address?.trim().isNotEmpty ?? false)
          ? p.address!
          : p.zipCode?.isNotEmpty == true
              ? 'ZIP ${p.zipCode}'
              : 'Unknown address';
      map.putIfAbsent(addr, () => []).add(p);
    }
    return map;
  }

  String _svcLabel(String? t) => categoryLabel(t);

  Color _svcColor(String? t) => categoryColor(t);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesProvider);
    final photosAsync   = ref.watch(profileDetailProvider(profileId));

    final profile = profilesAsync.valueOrNull
        ?.firstWhere((p) => p.id == profileId,
            orElse: () => ProfileModel(
                id: profileId,
                name: 'Profile',
                serviceType: 'standard'));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left,
              size: 20, color: _ink),
          onPressed: context.pop,
        ),
        title: Text(
          profile?.name ?? 'Profile',
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: _ink),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _hair),
        ),
      ),
      body: photosAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF7C3AED))),
        error: (e, _) => const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.xmark_circle, size: 40, color: _muted),
            SizedBox(height: 12),
            Text('Could not load photos',
                style: TextStyle(color: _muted)),
          ]),
        ),
        data: (photos) {
          final groups = _groupByAddress(photos);
          return CustomScrollView(
            slivers: [
              // ── Profile header ────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildProfileHeader(profile, photos.length),
              ),
              // ── Address groups ────────────────────────────────────────
              if (photos.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.camera,
                            size: 40, color: _muted),
                        SizedBox(height: 12),
                        Text('No photos yet',
                            style: TextStyle(color: _muted, fontSize: 15)),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final entry = groups.entries.toList()[i];
                      return _buildAddressGroup(
                          context, entry.key, entry.value, profile);
                    },
                    childCount: groups.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(ProfileModel? profile, int photoCount) {
    final isPrimary = profile?.primaryAddress?.isNotEmpty == true;
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service badge + photo count
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      _svcColor(profile?.serviceType).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _svcLabel(profile?.serviceType),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _svcColor(profile?.serviceType)),
                ),
              ),
              const Spacer(),
              Text(
                '$photoCount photo${photoCount != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
            ],
          ),
          if (profile?.note?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(profile!.note!,
                style: const TextStyle(fontSize: 13, color: _muted)),
          ],
          // Primary address
          if (isPrimary) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _soft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.building_2_fill,
                      size: 16, color: _purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Primary Address',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _purple)),
                        const SizedBox(height: 2),
                        Text(profile!.primaryAddress!,
                            style: const TextStyle(
                                fontSize: 13, color: _ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressGroup(BuildContext context, String address,
      List<PhotoModel> photos, ProfileModel? profile) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Address header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Icon(CupertinoIcons.location_fill,
                    size: 15, color: _purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _soft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${photos.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _purple)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _hair),
          // Photo grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: photos.length,
            itemBuilder: (_, i) {
              final photo = photos[i];
              return GestureDetector(
                onTap: () => PhotoPreviewGallery.open(
                  context,
                  photos: photos,
                  initialIndex: i,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: _fullUrl(photo.imageUrl),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            color: const Color(0xFFF3F4F6)),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF3F4F6),
                          child: const Icon(CupertinoIcons.photo,
                              size: 20, color: _muted),
                        ),
                      ),
                    ),
                    // Date overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          _shortDate(photo.timestamp),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
