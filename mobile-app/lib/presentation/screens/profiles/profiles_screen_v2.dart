import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/location_service.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';

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
            icon: const Icon(Icons.refresh_outlined),
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
                prefixIcon: const Icon(Icons.search_outlined),
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
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
                    .where((p) =>
                        p.name.toLowerCase().contains(_searchQuery) ||
                        p.serviceType.toLowerCase().contains(_searchQuery))
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
                        const Icon(Icons.folder_open_outlined, size: 48),
                        const SizedBox(height: 16),
                        const Text('No profiles found'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateProfileDialog(context),
                          icon: const Icon(Icons.add_outlined),
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
        child: const Icon(Icons.add_outlined),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, ProfileModel profile) {
    final serviceTypeColor = _getServiceTypeColor(profile.serviceType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: serviceTypeColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getServiceTypeIcon(profile.serviceType),
            color: serviceTypeColor,
          ),
        ),
        title: Text(profile.name),
        subtitle: Text(profile.serviceType.toUpperCase()),
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

  void _showCreateProfileDialog(BuildContext context) {
    final nameController = TextEditingController();
    var selectedServiceType = 'standard';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Profile'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'Enter profile name',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedServiceType,
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'rush', child: Text('ASAP')),
                  DropdownMenuItem(value: 'airport', child: Text('Airport')),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedServiceType = value);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }

              try {
                await ref.read(createProfileProvider(
                  (nameController.text, selectedServiceType),
                ).future);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile created')),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, ProfileModel profile) {
    final nameController = TextEditingController(text: profile.name);
    final noteController = TextEditingController(text: profile.note ?? '');
    var selectedServiceType = profile.serviceType;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedServiceType,
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'rush', child: Text('ASAP')),
                  DropdownMenuItem(value: 'airport', child: Text('Airport')),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedServiceType = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(updateProfileProvider(
                  (
                    profile.id,
                    nameController.text,
                    selectedServiceType,
                    noteController.text.isEmpty ? null : noteController.text,
                  ),
                ).future);

                // Refresh profiles list so note change is visible immediately
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

  Color _getServiceTypeColor(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'rush':
        return Colors.red;
      case 'airport':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  IconData _getServiceTypeIcon(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'rush':
        return Icons.local_fire_department_outlined;
      case 'airport':
        return Icons.flight_outlined;
      default:
        return Icons.check_circle_outlined;
    }
  }
}
