import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/utils/file_number.dart';
import '../../../core/utils/profile_lifecycle.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/profile_facts_card.dart';
import '../upload/attempt_draft_controller.dart';
import '../upload/attempt_limits.dart';

/// Profile detail: profile-specific info (header + addresses) above a
/// newest-first Service Attempts list. Tapping an attempt opens attempt
/// detail. "Add to Existing Profile" starts the attempt-only upload flow.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({required this.profileId, super.key});

  final int profileId;

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  // Shared light/purple theme — matches the rest of the app.
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = AppTheme.darkText;
  static const Color _muted = AppTheme.darkTextSecondary;
  static const Color _hair = AppTheme.darkBorder;
  static const Color _accent = AppTheme.primary;

  /// Collapse long attempt lists; user expands via "+N more".
  static const int _kInitialVisible = 5;
  bool _showAllAttempts = false;

  Future<void> _startAttempt() async {
    final known =
        ref.read(profileAttemptsProvider(widget.profileId)).valueOrNull?.length;
    final ok = await ensureCanStartNewAttempt(
      context,
      ref,
      profileId: widget.profileId,
      knownCount: known,
    );
    if (!ok || !context.mounted) return;
    ProfileModel? extra;
    final list = ref.read(profilesProvider).valueOrNull;
    if (list != null) {
      for (final p in list) {
        if (p.id == widget.profileId) {
          extra = p;
          break;
        }
      }
    }
    await context.push(
      '/new-attempt?profileId=${widget.profileId}',
      extra: extra,
    );
    if (!mounted) return;
    refreshProfileWork(ref, profileId: widget.profileId);
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final attemptsAsync = ref.watch(profileAttemptsProvider(widget.profileId));

    final profiles = profilesAsync.valueOrNull;
    ProfileModel? profile;
    if (profiles != null) {
      for (final p in profiles) {
        if (p.id == widget.profileId) {
          profile = p;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
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
      ),
      body: attemptsAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LoadingSkeleton(height: 72, borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
        error: (e, _) => const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.xmark_circle, size: 40, color: _muted),
            SizedBox(height: 12),
            Text('Could not load attempts',
                style: TextStyle(color: _muted)),
          ]),
        ),
        data: (attempts) {
          return RefreshIndicator(
            color: _accent,
            onRefresh: () async {
              refreshProfileWork(ref, profileId: widget.profileId);
              await ref.read(
                  profileAttemptsProvider(widget.profileId).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
              // ── Profile-specific information (above attempts) ───────────
              SliverToBoxAdapter(
                child: _buildProfileInfo(profile, attempts),
              ),
              SliverToBoxAdapter(
                child: _buildAttemptActions(
                  profile: profile,
                  attemptCount: attempts.length,
                ),
              ),
              SliverToBoxAdapter(
                child: _buildAddressesSection(context, profile),
              ),
              // ── Service Attempts ───────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildAttemptsHeader(attempts.length, profile),
              ),
              if (attempts.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyAttempts())
              else
                SliverToBoxAdapter(
                  child: _buildAttemptsList(attempts, profile),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttemptActions({
    required ProfileModel? profile,
    required int attemptCount,
  }) {
    final cap = attemptCapForProfile(profile);
    final blocked = profile != null && !profile.canAddAttempts;
    final atCap = blocked || attemptCount >= cap;
    String label = 'Add Attempt';
    if (blocked) {
      label = profileCanArchive(profile.status)
          ? 'Completed'
          : 'Archived';
    } else if (attemptCount >= cap) {
      label = 'Max attempts';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          if (profile != null && profile.canArchive)
            TextButton(
              onPressed: () => _archiveProfile(profile),
              child: const Text(
                'Mark archived',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _muted,
                ),
              ),
            ),
          const Spacer(),
          IntrinsicWidth(
            child: GestureDetector(
              onTap: atCap ? null : _startAttempt,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                decoration: BoxDecoration(
                  color: atCap ? const Color(0xFFE3E7EE) : _accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: atCap ? _muted : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _archiveProfile(ProfileModel profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this profile?'),
        content: const Text(
          'Use archive after you have independently verified payment. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(setProfileStatusProvider((
        profileId: profile.id,
        status: kProfileArchived,
      )).future);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile archived')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Widget _buildProfileInfo(ProfileModel? profile, List<Attempt> attempts) {
    if (profile == null) return const SizedBox.shrink();
    String? fileNumber;
    for (final a in attempts) {
      final fn = (a.fileNumber ?? '').trim();
      if (fn.isNotEmpty && fn.toUpperCase() != 'N/A') {
        fileNumber = fn;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileFactsCard(profile: profile, fileNumber: fileNumber),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: profileStatusColor(profile.status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              profileStatusLabel(profile.status),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: profileStatusColor(profile.status),
              ),
            ),
          ),
          if (profile.note?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(profile.note!,
                style: const TextStyle(fontSize: 13, color: _muted)),
          ],
        ],
      ),
    );
  }

  /// Addresses section — profile location shown as the Primary address.
  Widget _buildAddressesSection(BuildContext context, ProfileModel? profile) {
    final lines = <String>[
      if ((profile?.address ?? '').trim().isNotEmpty) profile!.address!.trim(),
      [
        profile?.city,
        profile?.state,
        profile?.postalCode,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
    ].where((s) => s.isNotEmpty).toList();
    final hasAddress = lines.isNotEmpty || (profile?.hasLocation ?? false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Addresses',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _muted)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.lightBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: hasAddress
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lines.isNotEmpty
                                  ? lines.join(', ')
                                  : '${profile!.latitude!.toStringAsFixed(5)}, '
                                      '${profile.longitude!.toStringAsFixed(5)}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                  height: 1.3),
                            ),
                            const SizedBox(height: 4),
                            const Text('Primary',
                                style: TextStyle(
                                    fontSize: 12, color: _muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(CupertinoIcons.location_solid,
                          color: _muted, size: 20),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(
                        child: Text('No address on this profile',
                            style: TextStyle(fontSize: 14, color: _muted)),
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          '/profiles-management',
                          extra: profile,
                        ),
                        child: const Text('Add',
                            style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptsHeader(int count, ProfileModel? profile) {
    final cap = attemptCapForProfile(profile);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          const Text('Service Attempts',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          const Spacer(),
          Text(
            '$count of $cap attempts',
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAttempts() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hair),
      ),
      child: Column(
        children: [
          const Icon(CupertinoIcons.doc_text, size: 36, color: _muted),
          const SizedBox(height: 12),
          const Text('No attempts yet',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 6),
          const Text(
            'Profile details stay pre-filled. Add the remaining attempt fields next.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _muted, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptsList(List<Attempt> attempts, ProfileModel? profile) {
    final visibleCount = _showAllAttempts
        ? attempts.length
        : attempts.length.clamp(0, _kInitialVisible);
    final hidden = attempts.length - visibleCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hair),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) const Divider(height: 1, color: _hair),
            _AttemptRow(
              attempt: attempts[i],
              profileFileNumber: profile?.fileNumber,
              onTap: () => context.push('/photo/${attempts[i].photoId}'),
            ),
          ],
          if (hidden > 0) ...[
            const Divider(height: 1, color: _hair),
            InkWell(
              onTap: () => setState(() => _showAllAttempts = true),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    '+$hidden more',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _muted),
                  ),
                ),
              ),
            ),
          ] else if (attempts.length > _kInitialVisible &&
              _showAllAttempts) ...[
            const Divider(height: 1, color: _hair),
            InkWell(
              onTap: () => setState(() => _showAllAttempts = false),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    'Show less',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _muted),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({
    required this.attempt,
    required this.onTap,
    this.profileFileNumber,
  });

  final Attempt attempt;
  final VoidCallback onTap;
  final String? profileFileNumber;

  static const Color _ink = Color(0xFF1A2130);
  static const Color _muted = Color(0xFF5C6778);
  static const Color _subtle = Color(0xFF8B95A5);
  static const Color _thumbBg = Color(0xFFE8EDF3);

  @override
  Widget build(BuildContext context) {
    final outcome = attempt.statusOption;
    final fileNo = inheritedFileNumber(
      profileFileNumber: profileFileNumber,
      attemptFileNumber: attempt.fileNumber,
    );
    final notes = (attempt.note ?? '').trim();
    final thumb = attempt.primaryPhoto?.imageUrl.trim() ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: thumb.isEmpty
                    ? const ColoredBox(
                        color: _thumbBg,
                        child: Icon(CupertinoIcons.photo,
                            size: 22, color: _subtle),
                      )
                    : CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(
                          color: _thumbBg,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: _thumbBg,
                          child: Icon(CupertinoIcons.photo,
                              size: 22, color: _subtle),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: outcome.softColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          outcome.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: outcome.color,
                          ),
                        ),
                      ),
                      if (fileNo.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'File $fileNo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notes.isEmpty ? 'No notes' : notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: notes.isEmpty ? _subtle : _muted,
                      height: 1.35,
                    ),
                  ),
                  if (attempt.displayTimestamp.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      attempt.displayTimestamp,
                      style: const TextStyle(fontSize: 12, color: _subtle),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 6),
              child: Icon(CupertinoIcons.chevron_right,
                  size: 16, color: _subtle),
            ),
          ],
        ),
      ),
    );
  }
}
