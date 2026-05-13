import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';

class ProfilesManagementScreen extends ConsumerStatefulWidget {

  const ProfilesManagementScreen({
    super.key,
    this.profileToEdit,
  });
  final ProfileModel? profileToEdit;

  @override
  ConsumerState<ProfilesManagementScreen> createState() =>
      _ProfilesManagementScreenState();
}

class _ProfilesManagementScreenState
    extends ConsumerState<ProfilesManagementScreen> {
  late TextEditingController _nameController;
  late TextEditingController _noteController;
  String _selectedServiceType = 'standard';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profileToEdit?.name ?? '',
    );
    _noteController = TextEditingController(
      text: widget.profileToEdit?.note ?? '',
    );
    _selectedServiceType = widget.profileToEdit?.serviceType ?? 'standard';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.profileToEdit != null) {
        // Update existing profile
        await ref.read(updateProfileProvider((
          widget.profileToEdit!.id,
          _nameController.text,
          _selectedServiceType,
          _noteController.text.isEmpty ? null : _noteController.text,
        )).future);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
        }
      } else {
        // Create new profile
        await ref.read(createProfileProvider((
          _nameController.text,
          _selectedServiceType,
        )).future);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile created successfully')),
          );
        }
      }

      // Refresh profiles list
      ref.invalidate(profilesProvider);

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const grayBg = Color(0xFFF8FAFC);
    const grayText = Color(0xFF475569);
    const grayBorder = Color(0xFFE2E8F0);
    const graySubtle = Color(0xFF94A3B8);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profileToEdit != null ? 'Edit Profile' : 'Add Profile',
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: grayText,
      ),
      backgroundColor: grayBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Name
            Text(
              'Profile Name',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: grayText,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Enter profile name',
                hintStyle: const TextStyle(color: graySubtle),
                prefixIcon: const Icon(Icons.person_outline, color: graySubtle),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: grayBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: grayBorder, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Service Type
            Text(
              'Service Type',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: grayText,
                  ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: grayBorder, width: 1),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedServiceType,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(
                    value: 'standard',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Standard'),
                        ],
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'rush',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Rush'),
                        ],
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'airport',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Airport'),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedServiceType = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 24),

            // Note
            Text(
              'Note (Optional)',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: grayText,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a note about this profile',
                hintStyle: const TextStyle(color: graySubtle),
                prefixIcon: const Icon(Icons.description_outlined, color: graySubtle),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: grayBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: grayBorder, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      widget.profileToEdit != null
                          ? 'Update Profile'
                          : 'Create Profile',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Cancel Button
            OutlinedButton(
              onPressed: _isLoading ? null : () => context.pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: grayBorder, width: 1.5),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
