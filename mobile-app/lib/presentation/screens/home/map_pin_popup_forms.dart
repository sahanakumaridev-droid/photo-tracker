part of 'map_pin_popup_sheet.dart';

extension _PinPopupFormsExt on _PinPopupSheetState {
  Widget _buildCarousel(List<PhotoModel> photos, PhotoModel ph) => GestureDetector(
      onHorizontalDragEnd: (details) {
        if (photos.length <= 1) return;
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          _rebuild(() => _photoIdx = (_photoIdx + 1) % photos.length);
        } else if (details.primaryVelocity! > 200) {
          _rebuild(
            () => _photoIdx = (_photoIdx - 1 + photos.length) % photos.length,
          );
        }
      },
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            CachedNetworkImage(
              imageUrl: ph.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: _surface,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: _surface,
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white38,
                  size: 40,
                ),
              ),
            ),

            // Prev / Next arrows
            if (photos.length > 1) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => _rebuild(
                      () => _photoIdx =
                          (_photoIdx - 1 + photos.length) % photos.length,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => _rebuild(
                      () => _photoIdx = (_photoIdx + 1) % photos.length,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              // Dot indicators
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: _photoIdx == i ? 14 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _photoIdx == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    )),
                ),
              ),
              // Counter badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_photoIdx + 1}/${photos.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],

            // + Add Photo button (top-left)
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _rebuild(() => _addingPhoto = !_addingPhoto);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _addingPhoto
                        ? Colors.red.withValues(alpha: 0.85)
                        : _accent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _addingPhoto ? '✕ Cancel' : '📷 + Add Photo',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

  // ── Add photo form ────────────────────────────────────────────────────────
  Widget _buildAddPhotoForm() {
    final profilesAsync = ref.watch(profilesProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📍 Adding photo at this pin location',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 10),

          // Profile selector
          profilesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (profiles) => DropdownButtonFormField<int>(
              initialValue: _addProfileId,
              dropdownColor: _surface,
              style: const TextStyle(color: _textPrimary, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              items: () {
                final nearbyIds = _nearbyProfileIds();
                // Only profiles within _kProfileProximityFt of this pin are
                // selectable — matches the proximity filter used elsewhere
                // in the upload flow.
                final nearby =
                    profiles.where((p) => nearbyIds.contains(p.id)).toList();
                return nearby
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('📍 ${p.name} (${p.serviceType})'),
                      ),
                    )
                    .toList();
              }(),
              onChanged: (v) => _rebuild(() => _addProfileId = v),
            ),
          ),
          const SizedBox(height: 10),

          // Photo picker
          if (_pickedFile == null)
            Row(
              children: [
                Expanded(
                  child: _addPhotoBtn(
                    label: '📷 Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _addPhotoBtn(
                    label: '🖼 Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_pickedFile!,
                            fit: BoxFit.cover, cacheWidth: 720),
                        // Live timestamp watermark — matches upload.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: WatermarkBar(
                            takenAtIso: _takenAt,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _rebuild(() {
                      _pickedFile = null;
                      _takenAt = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),

          // Note field
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [SentenceCaseInputFormatter()],
            style: const TextStyle(fontSize: 13, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Add a note… (optional)',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // File Number — only asked for when this profile has no file
          // number on record yet (legacy pins predating this requirement).
          // Otherwise it's silently carried forward from the existing photo.
          if (_existingFileNumberFor(_addProfileId) == null) ...[
            TextField(
              controller: _fileNumberCtrl,
              style: const TextStyle(fontSize: 13, color: _textPrimary),
              decoration: InputDecoration(
                hintText: 'File number (required) — e.g. 24-00123',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(builder: (_) {
                final isNa =
                    _fileNumberCtrl.text.trim().toUpperCase() == kFileNumberNA;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _rebuild(() {
                      if (isNa) {
                        _fileNumberCtrl.clear();
                      } else {
                        _fileNumberCtrl.text = kFileNumberNA;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isNa
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isNa
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      kFileNumberNA,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isNa
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
          ],

          // Upload button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_pickedFile != null &&
                      !_uploading &&
                      (_existingFileNumberFor(_addProfileId) != null ||
                          _fileNumberCtrl.text.trim().isNotEmpty))
                  ? _uploadPhoto
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _pickedFile != null ? _accent : Colors.white12,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '↑ Upload to this pin',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoBtn({required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
        ),
      );

  // ── Photo detail ──────────────────────────────────────────────────────────
  Widget _buildPhotoDetail(PhotoModel ph, PinProfileGroup group) => Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Profiles at this pin" label
          Text(
            'Profiles at this pin',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),

          // Profile rows — all groups
          ...widget.groups.map((g) {
            final c = _svcColor(g.serviceType);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                context.push('/photo/${g.photos.first.id}');
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g.profileName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _svcLabel(g.serviceType),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // Timestamp + coords
          if (ph.timestamp != null)
            _metaRow(Icons.access_time_rounded, _formatTs(ph.timestamp)),
          // Address line — human-readable with ZIP inline; tap to open Maps
          if (_fetchingAddress)
            _metaRow(Icons.location_on_rounded, 'Fetching address…')
          else if (_pinAddress != null)
            _metaRow(
              Icons.location_on_rounded,
              _pinAddress!,
              onTap: () => MapsLauncher.openLocation(
                address: _pinAddress,
                lat: ph.latitude,
                lng: ph.longitude,
              ),
            )
          else
            _metaRow(
              Icons.location_on_rounded,
              '${ph.latitude.toStringAsFixed(5)}, ${ph.longitude.toStringAsFixed(5)}',
              onTap: () => MapsLauncher.openLocation(
                lat: ph.latitude,
                lng: ph.longitude,
              ),
            ),
          // Coordinates always shown below address
          if (!_fetchingAddress)
            _metaRow(
              Icons.location_on_rounded,
              '${ph.latitude.toStringAsFixed(6)}, ${ph.longitude.toStringAsFixed(6)}',
            ),
          if (ph.note != null && ph.note!.isNotEmpty)
            _metaRow(Icons.description_outlined, ph.note!),

          const SizedBox(height: 12),

          // View Detail button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                context.push('/photo/${ph.id}');
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text(
                'View Full Detail',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );

  Widget _metaRow(IconData icon, String text, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: onTap != null ? _accent : _textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: onTap != null ? _accent : _textMuted,
                fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400,
                decoration:
                    onTap != null ? TextDecoration.underline : null,
                decorationColor: _accent,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: row,
    );
  }
}
