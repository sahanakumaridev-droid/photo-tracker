part of 'profiles_management_screen.dart';

extension _ProfilesManagementStepsExt on _ProfilesManagementScreenState {
  Widget _buildMiniMap(LatLng point) {
    return GestureDetector(
      onTap: _pickOnMap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 156,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    key: ValueKey(
                      '${point.latitude.toStringAsFixed(5)},'
                      '${point.longitude.toStringAsFixed(5)}',
                    ),
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      AppMapTiles.layer(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Tap to edit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'Profile Location',
              Icons.location_on_rounded,
              done: _hasLocation,
            ),
            const SizedBox(height: 6),
            _helper('Optional. Where this profile’s work is associated.'),
            if (_previewPoint != null) ...[
              const SizedBox(height: 12),
              _buildMiniMap(_previewPoint!),
            ],
            if (_hasLocation && _locationSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _successGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _successGreen.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: _successGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationSummary,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _actionTile(
                    onTap: _pickOnMap,
                    icon: Icons.map_outlined,
                    label: _hasLocation ? 'Edit on Map' : 'Set on Map',
                    primary: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _actionTile(
                    onTap: _locatingCurrent ? null : _useCurrentLocation,
                    icon: Icons.my_location_rounded,
                    label: 'Current',
                    loading: _locatingCurrent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              style: _fieldStyle,
              decoration: _deco(
                hint: 'Address',
                icon: Icons.apartment_rounded,
                voiceFor: _addressController,
              ),
              onChanged: (_) => _rebuild(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    style: _fieldStyle,
                    decoration: _deco(hint: 'City'),
                    onChanged: (_) => _rebuild(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.characters,
                    style: _fieldStyle,
                    decoration: _deco(hint: 'State'),
                    onChanged: (_) => _rebuild(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zipController,
              keyboardType: TextInputType.number,
              style: _fieldStyle,
              decoration: _deco(hint: 'ZIP Code'),
              onChanged: (_) => _rebuild(() {}),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _rebuild(() => _coordsExpanded = !_coordsExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _coordsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: _inkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _coordsExpanded
                          ? 'Hide coordinates'
                          : 'Show coordinates',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_coordsExpanded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: _fieldStyle,
                      decoration: _deco(hint: 'Latitude'),
                      onChanged: (_) => _rebuild(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: _fieldStyle,
                      decoration: _deco(hint: 'Longitude'),
                      onChanged: (_) => _rebuild(() {}),
                    ),
                  ),
                ],
              ),
            ],
            if (_hasLocation) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _clearLocation,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 15, color: _inkMuted),
                    SizedBox(width: 5),
                    Text(
                      'Clear Location',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  // ── Optional details ──────────────────────────────────────────────────────
  Widget _buildDetailsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Notes', Icons.description_outlined),
            if (_isEditing) ...[
              const SizedBox(height: 14),
              _fieldLabel('Note'),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [SentenceCaseInputFormatter()],
                style: _fieldStyle,
                decoration: _deco(
                  hint: 'Add a note about this profile',
                  icon: Icons.description_outlined,
                  voiceFor: _noteController,
                  voiceMode: VoiceFillMode.append,
                ),
              ),
            ],
          ],
        ),
      );

  bool get _nameDone => _nameController.text.trim().isNotEmpty;
  bool get _payoutDone =>
      int.tryParse(_payRateController.text.trim()) != null;
  bool get _deliveryDone =>
      _deliveryStyle != null && kDeliveryStyles.contains(_deliveryStyle);

  bool get _canAdvance {
    if (_step == 0) return _nameDone;
    if (_step == 1) return _deliveryDone;
    return true;
  }

  bool get _requiredComplete =>
      _nameDone && _deliveryDone;

  void _goNext() {
    if (!_canAdvance) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    if (_step < _stepCount - 1) {
      _rebuild(() => _step++);
    } else {
      _saveProfile();
    }
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    if (_step > 0) {
      _rebuild(() => _step--);
    } else {
      context.pop();
    }
  }

  Widget _buildStepHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _stepCount; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i <= _step ? _accent : _separator,
                    ),
                  ),
                _stepDot(i),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Step ${_step + 1} of $_stepCount',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _accent,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stepTitles[_step],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stepSubtitles[_step],
            style: const TextStyle(
              fontSize: 13.5,
              color: _inkMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDot(int index) {
    final done = index < _step;
    final active = index == _step;
    return GestureDetector(
      onTap: () {
        if (index == _step) return;
        // Only allow revisiting earlier steps from the indicator.
        if (index < _step) {
          FocusScope.of(context).unfocus();
          HapticFeedback.selectionClick();
          _rebuild(() => _step = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 28 : 22,
        height: active ? 28 : 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: (done || active) ? _btnGradient : null,
          color: (done || active) ? null : _separator,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : _inkSubtle,
                ),
              ),
      ),
    );
  }

  Widget _buildStepBody() {
    final nameDone = _nameDone;
    switch (_step) {
      case 0:
        return _buildIdentityCard(nameDone);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpeakFillBanner(
              hint: 'Say a company and pay, e.g. “First Legal, 125 dollars”',
              onDraft: _applyDraft,
            ),
            const SizedBox(height: 12),
            _buildCompanyCard(),
            _buildDetailsCard(),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpeakFillBanner(
              hint: 'Say the street, city, state, and ZIP',
              onDraft: _applyDraft,
            ),
            const SizedBox(height: 12),
            _buildLocationCard(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Sticky stepper CTA ────────────────────────────────────────────────────
  Widget _buildStickyFooter() {
    final canPrimary =
        _step < _stepCount - 1 ? _canAdvance : _requiredComplete;
    final primaryLabel = _isEditing ? 'Update Profile' : 'Create Profile';
    final primaryIcon =
        _isEditing ? Icons.check_rounded : Icons.add_rounded;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(
          top: BorderSide(color: _separator, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
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
          SizedBox(
            height: 54,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: (!_isLoading && canPrimary) ? _btnGradient : null,
                color: (_isLoading || !canPrimary) ? _separator : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: (!_isLoading && canPrimary)
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: (_isLoading || !canPrimary) ? null : _saveProfile,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _inkMuted,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                primaryIcon,
                                size: 20,
                                color: canPrimary
                                    ? Colors.white
                                    : _inkSubtle,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                primaryLabel,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: canPrimary
                                      ? Colors.white
                                      : _inkSubtle,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Name, company, and priority are required. Location is optional.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _inkSubtle,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

}
