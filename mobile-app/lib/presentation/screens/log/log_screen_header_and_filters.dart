part of 'log_screen_v2.dart';

extension _LogScreenHeaderExt on _LogScreenV2State {
  Widget _buildHeader(List<LogEntryModel> logs) => Container(
      color: _surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profiles',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.8,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedDate != null
                          ? DateFormat('EEEE, MMMM d')
                              .format(_selectedDate!)
                          : 'All field activity',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _inkSubtle,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final created =
                            await showCreateProfileDialog(context);
                        if (!mounted || created == null) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Profile "${created.name}" created'),
                            action: SnackBarAction(
                              label: 'Add attempt',
                              onPressed: () => context
                                  .push(
                                '/new-attempt?profileId=${created.id}',
                                extra: created,
                              ),
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(
                          'New Profile',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // ── Send selected — only while selecting, and only once
              // something is chosen. Emails logged data + photo.
              if (_selectionMode && _selectedLogIds.isNotEmpty)
                GestureDetector(
                  onTap: () => _sendSelected(logs),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.paperplane_fill,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Send (${_selectedLogIds.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                      ],
                    ),
                  ),
                ),
              // ── Select toggle ──
              if (logs.isNotEmpty)
                GestureDetector(
                  onTap: _toggleSelectionMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Text(_selectionMode ? 'Cancel' : 'Select',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );

  // ── Search ────────────────────────────────────────────────────────────────
  Widget _buildSearchRow() => Container(
      color: _filterBar,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _searchFocused ? _accent : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: _searchFocused
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (v) => _rebuild(() => _searchQuery = v),
          style: const TextStyle(
            fontSize: 15,
            color: _ink,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Say a profile, note, or location…',
            hintStyle: const TextStyle(
              color: _inkSubtle,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Icon(
                CupertinoIcons.search,
                size: 20,
                color: _searchFocused ? _accent : _inkSubtle,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VoiceMicButton(
                    controller: _searchController,
                    onChanged: (v) => _rebuild(() => _searchQuery = v),
                  ),
                  // Clear button — only when typing
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _rebuild(() => _searchQuery = '');
                        _searchController.clear();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _inkSubtle.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 13,
                          color: _inkMuted,
                        ),
                      ),
                    ),
                  // Filter icon with badge
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _hasFilters ? _accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            CupertinoIcons.slider_horizontal_3,
                            size: 19,
                            color: _hasFilters ? _accent : _inkSubtle,
                          ),
                        ),
                        if (_filterCount > 0)
                          Positioned(
                            top: -2,
                            right: 6,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$_filterCount',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleXY(
                                  begin: 0.8,
                                  end: 1,
                                  duration: 600.ms,
                                  curve: Curves.easeInOut,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 0,
              vertical: 13,
            ),
          ),
        ),
      ),
    );

  // ── Active filter chips ───────────────────────────────────────────────────
  Widget _buildActiveFilters() => Container(
      color: _filterBar,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedDate != null)
                    _activeChip(
                      label: _startTime != null || _endTime != null
                          ? '${DateFormat('MMM d').format(_selectedDate!)} '
                            '${_startTime?.format(context) ?? '00:00'}'
                            '–${_endTime?.format(context) ?? 'end'}'
                          : DateFormat('MMM d').format(_selectedDate!),
                      icon: CupertinoIcons.calendar,
                      color: _accent,
                      onRemove: () => _rebuild(() {
                        _selectedDate = null;
                        _startTime = null;
                        _endTime = null;
                      }),
                    ),
                  if (_selectedCategory != null) ...[
                    if (_selectedDate != null)
                      const SizedBox(width: 6),
                    _activeChip(
                      label: categoryOf(_selectedCategory).label,
                      icon: categoryOf(_selectedCategory).icon,
                      color: categoryOf(_selectedCategory).color,
                      onRemove: () =>
                          _rebuild(() => _selectedCategory = null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _clearFilters,
            child: const Text(
              'Clear',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _activeChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onRemove,
  }) =>
      Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 5, bottom: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.xmark, size: 10, color: color),
              ),
            ),
          ],
        ),
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(
    AsyncValue<List<LogEntryModel>> logAsync,
    dynamic userPos,
  ) =>
      logAsync.when(
        loading: _buildSkeleton,
        error: (err, _) => _buildError(err),
        data: (allLogs) {
          final merged = _withProfilesWithoutAttempts(allLogs);
          if (merged.isEmpty) return _buildEmpty();
          final logs = _applyClientFilters(merged);
          if (logs.isEmpty) return _buildEmpty();
          return _buildGroupedList(logs, userPos);
        },
      );

  // ── Skeleton loader ───────────────────────────────────────────────────────
  Widget _buildSkeleton() => ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFE5E7EB),
          highlightColor: const Color(0xFFF9FAFB),
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );

  List<LogEntryModel> _latestFirst(List<LogEntryModel> logs) {
    final newest = <String, LogEntryModel>{};
    for (final log in logs) {
      final profileKey = log.profileId?.toString() ??
          log.profileName ??
          log.id.toString();
      final prev = newest[profileKey];
      if (prev == null ||
          (log.timestamp ?? '').compareTo(prev.timestamp ?? '') > 0) {
        newest[profileKey] = log;
      }
    }
    final items = newest.values.toList()
      ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return items;
  }

  // ── Grouped list ──────────────────────────────────────────────────────────
  Widget _buildGroupedList(List<LogEntryModel> logs, dynamic userPos) {
    final items = _latestFirst(logs);

    return RefreshIndicator(
      color: _accent,
      backgroundColor: _surface,
      onRefresh: () async { ref.invalidate(logProvider(_filters)); },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _buildLogCard(items[index], index, userPos)
              .animate()
              .fadeIn(
                duration: 350.ms,
                delay: Duration(milliseconds: index * 40),
              )
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 350.ms,
                delay: Duration(milliseconds: index * 40),
                curve: Curves.easeOut,
              );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String label, int count) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _inkMuted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _separator,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _inkSubtle,
              ),
            ),
          ),
        ],
      ),
    );

  // ── Selection radio ────────────────────────────────────────────────────────
  Widget _selectCircle(bool selected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _accent : _inkSubtle,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(CupertinoIcons.checkmark, size: 15, color: Colors.white)
            : null,
      );

}
