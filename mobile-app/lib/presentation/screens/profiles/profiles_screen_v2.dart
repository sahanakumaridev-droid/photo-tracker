import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/text_formatters.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/create_profile_dialog.dart';

class ProfilesScreenV2 extends ConsumerStatefulWidget {
  const ProfilesScreenV2({super.key});

  @override
  ConsumerState<ProfilesScreenV2> createState() => _ProfilesScreenV2State();
}

class _ProfilesScreenV2State extends ConsumerState<ProfilesScreenV2> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            onPressed: () => ref.refresh(profilesProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search profiles...',
                prefixIcon: const Icon(CupertinoIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),
          // Profiles List
          Expanded(
            child: profilesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: $error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.refresh(profilesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (profiles) {
                final filtered = profiles
                    .where((p) => p.name.toLowerCase().contains(_searchQuery))
                    .toList();

                // Sort by distance from current user location
                final locationAsync = ref.watch(currentLocationProvider);
                final userPos = locationAsync.valueOrNull;
                final photosAsync = ref.watch(photosProvider);
                final photos = photosAsync.valueOrNull ?? [];

                if (userPos != null) {
                  filtered.sort((a, b) {
                    // Find the most recent photo for each profile to get its location
                    final aPhotos = photos
                        .where((ph) =>
                            ph.profileId == a.id ||
                            (ph.profiles?.any((pr) => pr.id == a.id) ?? false))
                        .toList();
                    final bPhotos = photos
                        .where((ph) =>
                            ph.profileId == b.id ||
                            (ph.profiles?.any((pr) => pr.id == b.id) ?? false))
                        .toList();

                    if (aPhotos.isEmpty && bPhotos.isEmpty) return 0;
                    if (aPhotos.isEmpty) return 1;
                    if (bPhotos.isEmpty) return -1;

                    final aLatest = aPhotos.reduce((x, y) =>
                        (x.timestamp ?? '').compareTo(y.timestamp ?? '') > 0
                            ? x
                            : y);
                    final bLatest = bPhotos.reduce((x, y) =>
                        (x.timestamp ?? '').compareTo(y.timestamp ?? '') > 0
                            ? x
                            : y);

                    final aDist = LocationService.calculateDistance(
                      userPos.latitude, userPos.longitude,
                      aLatest.latitude, aLatest.longitude,
                    );
                    final bDist = LocationService.calculateDistance(
                      userPos.latitude, userPos.longitude,
                      bLatest.latitude, bLatest.longitude,
                    );
                    return aDist.compareTo(bDist);
                  });
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.folder_open, size: 48),
                        const SizedBox(height: 16),
                        const Text('No profiles found'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateProfileDialog(context),
                          icon: const Icon(CupertinoIcons.add),
                          label: const Text('Create Profile'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildProfileCard(context, filtered[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateProfileDialog(context),
        child: const Icon(CupertinoIcons.add),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, ProfileModel profile) {
    const accent = Color(0xFF5B5BD6);
    final note = profile.note;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(CupertinoIcons.person_fill, color: accent),
        ),
        title: Text(profile.name),
        subtitle: (note != null && note.isNotEmpty) ? Text(note) : null,
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              child: const Text('Edit'),
              onTap: () => _showEditProfileDialog(context, profile),
            ),
            PopupMenuItem(
              child: const Text('Delete'),
              onTap: () => _showDeleteConfirmation(context, profile),
            ),
          ],
        ),
        onTap: () => context.push('/profile/${profile.id}'),
      ),
    );
  }

  Future<void> _showCreateProfileDialog(BuildContext context) async {
    final created = await showCreateProfileDialog(context);
    if (!context.mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Profile "${created.name}" created')),
    );
  }

  void _showEditProfileDialog(BuildContext context, ProfileModel profile) {
    final nameController = TextEditingController(text: profile.name);
    final noteController = TextEditingController(text: profile.note ?? '');
    final payRateController =
        TextEditingController(text: profile.payRate?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: const [TitleCaseInputFormatter()],
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: const [SentenceCaseInputFormatter()],
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: payRateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Pay Rate', prefixText: r'$'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(updateProfileProvider((
                  profileId: profile.id,
                  name: nameController.text,
                  // Service level is no longer a profile property; preserve
                  // whatever was stored so the update is a no-op for it.
                  serviceType: profile.serviceType,
                  company: profile.company,
                  note: noteController.text.isEmpty ? null : noteController.text,
                  payRate: int.tryParse(payRateController.text.trim()),
                  deliveryStyle: profile.deliveryStyle,
                  // This dialog only edits name/note/pay rate — preserve
                  // whatever Status/Profile Location was already stored so
                  // saving here can't silently wipe them.
                  status: profile.status,
                  address: profile.address,
                  city: profile.city,
                  state: profile.state,
                  postalCode: profile.postalCode,
                  latitude: profile.latitude,
                  longitude: profile.longitude,
                )).future);
                ref.invalidate(profilesProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save: ${e.toString().replaceAll('Exception: ', '')}')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ProfileModel profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Are you sure you want to delete "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(deleteProfileProvider(profile.id).future);
                ref.invalidate(profilesProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

}
