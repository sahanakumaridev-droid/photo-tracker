import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../data/models/attempt.dart';
import '../../../data/models/company.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/loading_skeleton.dart';
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
  static const Color _surface = Color(0xFF1C222E);
  static const Color _ink = AppTheme.darkText;
  static const Color _muted = AppTheme.darkTextSecondary;
  static const Color _hair = AppTheme.darkBorder;
  static const Color _accent = AppTheme.primary;

  /// Collapse long attempt lists; user expands via "+N more".
  static const int _kInitialVisible = 4;
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
    context.push('/upload?profileId=${widget.profileId}');
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

    final attemptCount = attemptsAsync.valueOrNull?.length ?? 0;
    final atCap =
        attemptCount >= AttemptDraftController.kMaxAttemptsPerJob;

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
        actions: [
          TextButton.icon(
            onPressed: _startAttempt,
            icon: Icon(
              atCap ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.plus,
              size: 16,
              color: atCap ? const Color(0xFFFBBF24) : _accent,
            ),
            label: Text(
              atCap
                  ? 'Max ${AttemptDraftController.kMaxAttemptsPerJob} attempts'
                  : 'Add to Existing Profile',
              style: TextStyle(
                  color: atCap ? const Color(0xFFFBBF24) : _accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
        ],
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
          return CustomScrollView(
            slivers: [
              // ── Profile-specific information (above attempts) ───────────
              SliverToBoxAdapter(
                child: _buildProfileInfo(profile, attempts.length),
              ),
              SliverToBoxAdapter(
                child: _buildAddressesSection(context, profile),
              ),
              // ── Service Attempts ───────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildAttemptsHeader(attempts.length),
              ),
              if (attempts.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyAttempts())
              else
                SliverToBoxAdapter(
                  child: _buildAttemptsList(attempts),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileInfo(ProfileModel? profile, int attemptCount) {
    final company = companyById(profile?.company);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (company != null) ...[
            Text(company.name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _muted)),
            const SizedBox(height: 4),
            Text(company.email,
                style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 4),
            Text(
              '${company.attemptsForDiligence} diligence attempts · '
              '${company.payoutScheduleDescription}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 6),
          ],
          if (profile?.isAwaitingAttempt == true) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Awaiting Attempt',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.warning)),
            ),
            const SizedBox(height: 10),
          ],
          if (profile?.note?.isNotEmpty == true)
            Text(profile!.note!,
                style: const TextStyle(fontSize: 13, color: _muted)),
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

  Widget _buildAttemptsHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          const Text('Service Attempts',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          const Spacer(),
          Text(
            '$count Attempt${count == 1 ? '' : 's'}',
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
            'Add an attempt to this profile — only attempt details will be collected.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _muted, height: 1.35),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _startAttempt,
            icon: const Icon(CupertinoIcons.plus, size: 16),
            label: const Text('Add to Existing Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptsList(List<Attempt> attempts) {
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
  const _AttemptRow({required this.attempt, required this.onTap});

  final Attempt attempt;
  final VoidCallback onTap;

  static const Color _ink = AppTheme.lightText;
  static const Color _muted = AppTheme.lightTextSecondary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attempt.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    attempt.noteSnippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: _muted, height: 1.35),
                  ),
                  if (attempt.displayTimestamp.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      attempt.displayTimestamp,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 8),
              child: Icon(CupertinoIcons.chevron_right,
                  size: 16, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}
