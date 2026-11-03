part of 'attempt_composer_screen.dart';

extension _AttemptComposerCardsExt on _AttemptComposerScreenState {
  Widget _buildJobCard(AsyncValue<List<ProfileModel>> profilesAsync) {
    final locked = controller.isExistingProfileAttempt;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Job', Icons.badge_outlined),
          const SizedBox(height: 12),
          if (locked)
            _lockedRow(
              controller.selectedProfile?.name ?? 'Loading profile…',
              subtitle: companyOrDefault(controller.companyId).name,
            )
          else ...[
            _fieldCaption('Company'),
            const SizedBox(height: 6),
            CompanyDropdown(
              value: controller.companyId,
              onChanged: controller.setCompany,
            ),
            const SizedBox(height: 14),
            _fieldCaption('Profile'),
            const SizedBox(height: 6),
            profilesAsync.when(
              loading: () => _shimmer(height: 48),
              error: (_, __) => _errorBox('Failed to load profiles'),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return _Pressable(
                    onTap: _createProfile,
                    child: _secondaryAction(
                      icon: Icons.add_rounded,
                      label: 'Add Profile',
                      filled: true,
                    ),
                  );
                }
                return _Pressable(
                  onTap: () => _showProfilePicker(profiles),
                  child: _selectRow(
                    value: controller.selectedProfile?.name,
                    placeholder: 'Select a profile',
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServedToCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldCaption('Served to', optional: true),
          const SizedBox(height: 6),
          _Pressable(
            onTap: () => _showServedToPicker(context),
            child: _selectRow(
              value: controller.servedToController.text.trim().isEmpty
                  ? null
                  : controller.servedToController.text.trim(),
              placeholder: 'Who was served',
            ),
          ),
          if (controller.servedToController.text.trim().isNotEmpty &&
              AttemptDraftController.servedToNeedsRelation(
                  controller.servedToController.text)) ...[
            const SizedBox(height: 14),
            _fieldCaption('Relation to'),
            const SizedBox(height: 6),
            _inputField(
              controller: controller.relationToController,
              hint: 'e.g. Spouse, coworker',
              icon: Icons.groups_outlined,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcomeSegment() {
    final options = kAttemptStatuses
        .where((s) => s.value != kAttemptStatusPending)
        .toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final s in options)
            Expanded(
              child: _Pressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.setAttemptStatus(s.value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: controller.attemptStatus == s.value
                        ? _surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: controller.attemptStatus == s.value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: controller.attemptStatus == s.value
                          ? s.color
                          : _inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Outcome', Icons.flag_rounded),
          const SizedBox(height: 8),
          _outcomeSegment(),
          const SizedBox(height: 14),
          _sectionLabel('Notes', Icons.edit_outlined),
          const SizedBox(height: 8),
          _inputField(
            controller: controller.noteController,
            hint: 'Tap the mic and talk the note',
            icon: Icons.description_outlined,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [SentenceCaseInputFormatter()],
            voice: true,
            voiceMode: VoiceFillMode.append,
          ),
          const SizedBox(height: 10),
          NoteSuggestionChips(
            controller: controller.noteController,
            outcome: controller.attemptStatus,
            onChanged: controller.bump,
          ),
          if (controller.isSuccessfulAttempt) ...[
            const SizedBox(height: 10),
            SubjectDescriptionForm(
              description: controller.subjectDescription,
              onChanged: controller.bump,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayAndAddress() {
    return const SizedBox.shrink();
  }

  Widget _buildLinkProfilesCard() {
    if (controller.selectedProfile == null) return const SizedBox.shrink();
    final nearby = controller.nearbyLinkProfiles(ref);
    if (nearby.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Link profiles', Icons.link_rounded, optional: true),
          const SizedBox(height: 6),
          Text(
            'Duplicate this attempt onto nearby profiles after you save. '
            'Only shown when another profile is within '
            '${AttemptDraftController.kProfileProximityFt.toInt()} ft.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: _inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in nearby)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.toggleLinkProfile(p.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: controller.linkProfileIds.contains(p.id)
                          ? _accentSoft
                          : _canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: controller.linkProfileIds.contains(p.id)
                            ? _accent
                            : _separator,
                        width: controller.linkProfileIds.contains(p.id)
                            ? 1.5
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          controller.linkProfileIds.contains(p.id)
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 20,
                          color: controller.linkProfileIds.contains(p.id)
                              ? _accent
                              : _inkSubtle,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    final canUpload = controller.canUpload;
    final isInProgress = controller.uploadState ==
            AttemptUploadState.uploading ||
        controller.uploadState == AttemptUploadState.processing;
    final tappable =
        canUpload && controller.uploadState == AttemptUploadState.idle;

    String completeLabel;
    if (controller.uploadState == AttemptUploadState.uploading) {
      final total = controller.selectedImages.length;
      completeLabel = total > 1
          ? 'Uploading ${controller.uploadedCount + 1} of $total…'
          : 'Uploading photo…';
    } else if (controller.uploadState == AttemptUploadState.processing) {
      completeLabel = 'Processing…';
    } else if (canUpload) {
      completeLabel = widget.isEditing ? 'Save changes' : 'Complete Attempt';
    } else if (!controller.hasPhoto) {
      completeLabel = 'Take photo';
    } else {
      completeLabel = controller.missingFieldsHint();
    }
    final primaryReady = canUpload || isInProgress || !controller.hasPhoto;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(top: BorderSide(color: _separator, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInProgress) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                backgroundColor: _accent.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(_accentMid),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: isInProgress ? null : _saveAndExit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkMuted,
                      side: const BorderSide(color: _separator, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Save & exit',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: primaryReady ? _btnGradient : null,
                      color: primaryReady ? null : _elevated,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: tappable
                          ? [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.38),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: ElevatedButton(
                      onPressed: isInProgress
                          ? null
                          : () {
                              if (tappable) {
                                controller.upload(context, ref);
                              } else if (!controller.hasPhoto) {
                                controller.pickImage(
                                  context,
                                  ImageSource.camera,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor: _inkSubtle,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        completeLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primaryReady ? Colors.white : _inkSubtle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndExit() async {
    HapticFeedback.lightImpact();
    if (controller.canQuickSave) {
      final saved = await controller.quickSaveAttempt(context);
      if (!saved || !mounted) return;
    } else {
      controller.saveDraft();
    }
    ref.invalidate(localSnapshotsProvider);
    _leave();
  }

  void _leave() {
    refreshProfileWork(
      ref,
      profileId: controller.selectedProfile?.id ?? controller.initialProfileId,
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (controller.isExistingProfileAttempt) {
      context.go('/log');
    } else {
      context.go('/upload');
    }
  }

  Widget _buildSuccessSummary() {
    final n = controller.uploadedCount > 0
        ? controller.uploadedCount
        : controller.selectedImages.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: _successGreen, size: 40),
          ),
          const SizedBox(height: 20),
          const Text(
            'Attempt saved',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            n > 1
                ? '$n photos logged successfully'
                : 'Photo logged successfully',
            style: const TextStyle(fontSize: 14, color: _inkMuted),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _separator),
            ),
            child: Column(
              children: [
                _summaryRow(
                    'Profile', controller.selectedProfile?.name ?? '—'),
                const Divider(height: 20, color: _separator),
                _summaryRowWidget(
                    'Priority',
                    PriorityChip(category: controller.selectedCategory)),
                const Divider(height: 20, color: _separator),
                _summaryRowWidget(
                    'Status', StatusChip(status: controller.attemptStatus)),
                const Divider(height: 20, color: _separator),
                _summaryRow(
                  'File #',
                  (controller.selectedProfile?.fileNumber ?? '')
                          .trim()
                          .isEmpty
                      ? '—'
                      : controller.selectedProfile!.fileNumber!.trim(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _inkMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
          ),
        ),
      ],
    );
  }

  Widget _summaryRowWidget(String label, Widget value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _inkMuted)),
        const Spacer(),
        value,
      ],
    );
  }

  Widget _buildSuccessFooter() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _separator, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          if (controller.lastUploadedPhotoId != null)
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      context.push('/photo/${controller.lastUploadedPhotoId}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View post',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          if (controller.lastUploadedPhotoId != null) const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _leave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _successGreen,
                  side: BorderSide(
                      color: _successGreen.withValues(alpha: 0.4), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile picker ──────────────────────────────────────────────────────
}
