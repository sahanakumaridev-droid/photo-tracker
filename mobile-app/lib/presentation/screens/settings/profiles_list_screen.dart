import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';

class ProfilesListScreen extends ConsumerWidget {
  const ProfilesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesProvider);

    const grayBg = Color(0xFFF8FAFC);
    const grayText = Color(0xFF475569);
    const graySubtle = Color(0xFF94A3B8);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: grayText,
      ),
      backgroundColor: grayBg,
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.withValues(alpha: 0.5),
              ),
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
        data: (profiles) => Column(
          children: [
            Expanded(
              child: profiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.folder_outlined,
                            size: 64,
                            color: graySubtle,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Profiles Yet',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: grayText,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Create your first profile to get started',
                            style: TextStyle(
                              color: graySubtle,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => context.push('/profiles-management'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create Profile'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: profiles.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        return _buildProfileCard(context, profile);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/profiles-management'),
        icon: const Icon(Icons.add),
        label: const Text('Add Profile'),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, ProfileModel profile) {
    final serviceTypeColor = _getServiceTypeColor(profile.serviceType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
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
          onTap: () => context.push(
            '/profiles-management',
            extra: profile,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: serviceTypeColor.withValues(alpha: 0.2),
                  ),
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: serviceTypeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.serviceType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: serviceTypeColor,
                        ),
                      ),
                      if (profile.note != null && profile.note!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          profile.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_outlined,
                  size: 24,
                  color: Color(0xFFE2E8F0),
                ),
              ],
            ),
          ),
        ),
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
}
