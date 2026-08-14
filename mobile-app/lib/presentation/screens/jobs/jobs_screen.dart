import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/company.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/upload_app_bar_button.dart';
import '../upload/attempt_draft_controller.dart';
import '../upload/attempt_limits.dart';

/// List of the same jobs shown as pins on the map.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  final _searchCtrl = TextEditingController();

  static const _ink = AppTheme.darkText;
  static const _muted = AppTheme.darkTextSecondary;
  static const _accent = AppTheme.primary;
  static const _surface = AppTheme.darkSurface;
  static const _bg = AppTheme.darkBg;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(currentLocationProvider);
    await Future.wait([
      ref.refresh(photosProvider.future),
      ref.refresh(profilesProvider.future),
    ]);
  }

  List<_JobRow> _jobs(List<ProfileModel> profiles, List<PhotoModel> photos) {
    final used = <int>{};
    final rows = <_JobRow>[];

    for (final profile in profiles) {
      final pPhotos = photos
          .where((ph) =>
              ph.profileId == profile.id ||
              (ph.profiles?.any((p) => p.id == profile.id) ?? false))
          .toList()
        ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      for (final p in pPhotos) {
        used.add(p.id);
      }
      rows.add(_JobRow(profile: profile, photos: pPhotos));
    }

    final leftover = photos.where((p) =>
        !used.contains(p.id) && (p.latitude != 0 || p.longitude != 0));
    final groups = <String, List<PhotoModel>>{};
    for (final p in leftover) {
      final key =
          '${p.latitude.toStringAsFixed(5)}_${p.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    for (final g in groups.values) {
      g.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      rows.add(_JobRow(profile: null, photos: g));
    }
    return rows;
  }

  List<_JobRow> _filtered(List<_JobRow> jobs) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return jobs;
    return jobs.where((j) {
      final hay = [
        j.jobId,
        j.recipient,
        j.address,
        j.client ?? '',
        j.zip,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  double? _distanceMi(_JobRow job, Position pos) {
    if (job.lat == null || job.lng == null) return null;
    final km = LocationService.calculateDistance(
        pos.latitude, pos.longitude, job.lat!, job.lng!);
    return km * 0.621371;
  }

  String? _distanceLabel(_JobRow job, Position? pos) {
    if (pos == null) return null;
    final mi = _distanceMi(job, pos);
    if (mi == null) return null;
    if (mi < 0.1) return 'Nearby';
    return '${mi.toStringAsFixed(1)} mi';
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final photosAsync = ref.watch(photosProvider);
    final userPos = ref.watch(currentLocationProvider).valueOrNull;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          SizedBox(height: topPad + 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Jobs',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _refresh();
                  },
                  icon: const Icon(Icons.refresh_rounded, color: _muted),
                ),
                const UploadAppBarButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _SearchField(controller: _searchCtrl),
          ),
          Expanded(
            child: profilesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: _accent),
              ),
              error: (e, _) => _ErrorState(onRetry: _refresh),
              data: (profiles) {
                final photos = photosAsync.valueOrNull ?? const <PhotoModel>[];
                var jobs = _jobs(profiles, photos);
                if (userPos != null) {
                  jobs = [...jobs]..sort((a, b) {
                    final da = _distanceMi(a, userPos);
                    final db = _distanceMi(b, userPos);
                    if (da == null && db == null) return 0;
                    if (da == null) return 1;
                    if (db == null) return -1;
                    return da.compareTo(db);
                  });
                }
                jobs = _filtered(jobs);
                if (jobs.isEmpty) {
                  return _EmptyState(
                    searching: _searchCtrl.text.trim().isNotEmpty,
                    onClear: () => _searchCtrl.clear(),
                  );
                }
                return RefreshIndicator(
                  color: _accent,
                  backgroundColor: _surface,
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final job = jobs[i];
                      return _JobCard(
                        jobId: job.jobId,
                        distance: _distanceLabel(job, userPos),
                        recipient: job.recipient,
                        address: job.address,
                        client: job.client,
                        attempts: job.attemptCount,
                        atCap: job.attemptCount >=
                            AttemptDraftController.kMaxAttemptsPerJob,
                        onNewAttempt: () async {
                          final pid = job.profile?.id;
                          final ok = await ensureCanStartNewAttempt(
                            context,
                            ref,
                            profileId: pid,
                            knownCount: job.attemptCount,
                          );
                          if (!ok || !context.mounted) return;
                          if (pid != null) {
                            context.push('/upload?profileId=$pid');
                          } else {
                            context.push('/upload');
                          }
                        },
                        onViewJob: () {
                          final pid = job.profile?.id;
                          if (pid != null) {
                            context.push('/profile/$pid');
                          } else if (job.photos.isNotEmpty) {
                            context.push('/photo/${job.photos.first.id}');
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _JobRow {
  _JobRow({required this.profile, required this.photos});

  final ProfileModel? profile;
  final List<PhotoModel> photos;

  int get attemptCount => jobAttemptCount(
        photos: photos,
        profileAttemptsCount: profile?.attemptsCount,
      );

  PhotoModel? get latest => photos.isEmpty ? null : photos.first;

  String get jobId {
    final fn = latest?.fileNumber?.trim();
    if (fn != null && fn.isNotEmpty) return fn;
    if (profile != null) return '${profile!.id}';
    return latest != null ? '${latest!.id}' : '—';
  }

  String get recipient {
    final name = profile?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    final fromPhoto = latest?.profileName?.trim();
    if (fromPhoto != null && fromPhoto.isNotEmpty) return fromPhoto;
    return 'Unknown';
  }

  String get address {
    final fromPhoto = latest?.address?.trim();
    if (fromPhoto != null && fromPhoto.isNotEmpty) return fromPhoto;
    final parts = [
      profile?.address,
      profile?.city,
      profile?.state,
      profile?.postalCode,
    ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
    if (parts.isNotEmpty) return parts.join(', ');
    final zip = latest?.zipCode?.trim();
    if (zip != null && zip.isNotEmpty) return 'ZIP $zip';
    if (lat != null && lng != null) {
      return '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}';
    }
    return 'No address';
  }

  String get zip =>
      (latest?.zipCode ?? profile?.postalCode ?? '').trim();

  String? get client {
    final named = profile?.companyName?.trim();
    if (named != null && named.isNotEmpty) return named;
    if (profile != null) return companyOrDefault(profile!.company).name;
    return null;
  }

  double? get lat => latest?.latitude ?? profile?.latitude;
  double? get lng => latest?.longitude ?? profile?.longitude;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xE61C222E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded,
                color: AppTheme.darkTextTertiary, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, color: AppTheme.darkText),
              decoration: const InputDecoration(
                hintText: 'Job number, recipient, zip',
                hintStyle: TextStyle(
                    color: AppTheme.darkTextTertiary, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: controller.clear,
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.darkTextTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.jobId,
    required this.recipient,
    required this.address,
    required this.attempts,
    required this.onNewAttempt,
    required this.onViewJob,
    this.distance,
    this.client,
    this.atCap = false,
  });

  final String jobId;
  final String? distance;
  final String recipient;
  final String address;
  final String? client;
  final int attempts;
  final bool atCap;
  final VoidCallback onNewAttempt;
  final VoidCallback onViewJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(jobId,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkTextSecondary)),
              const Spacer(),
              if (distance != null)
                Text(distance!,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.darkTextSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recipient,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.darkText,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            address,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
              height: 1.3,
            ),
          ),
          if (client != null && client!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Client',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.darkTextSecondary)),
            const SizedBox(height: 2),
            Text(client!,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkText)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.darkElevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$attempts of ${AttemptDraftController.kMaxAttemptsPerJob} '
              'attempt${attempts == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: atCap
                      ? const Color(0xFFFBBF24)
                      : AppTheme.darkTextSecondary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: atCap ? Icons.block_rounded : Icons.add_rounded,
                  label: atCap ? 'Max attempts' : 'New Attempt',
                  filled: !atCap,
                  onTap: onNewAttempt,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.visibility_outlined,
                  label: 'View Job',
                  filled: false,
                  onTap: onViewJob,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: filled ? AppTheme.primary : const Color(0xFF2A3340),
            borderRadius: BorderRadius.circular(24),
            border: filled ? null : Border.all(color: AppTheme.darkBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching, required this.onClear});
  final bool searching;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.work_outline_rounded,
                size: 44, color: AppTheme.darkTextTertiary),
            const SizedBox(height: 12),
            Text(
              searching ? 'No jobs match that search' : 'No jobs yet',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a job number, recipient, or ZIP.'
                  : 'Jobs from the map show up here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.darkTextSecondary),
            ),
            if (searching) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onClear, child: const Text('Clear search')),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AppTheme.darkTextTertiary),
          const SizedBox(height: 12),
          const Text('Could not load jobs',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
