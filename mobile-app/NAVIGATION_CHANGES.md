# Navigation Changes - Profiles Moved to Settings

## Before: 6 Tabs

```
┌──────────────────────────────────────────────────────┐
│  Home  │  Map  │ Profiles │ Upload │  Log  │ Settings │
└──────────────────────────────────────────────────────┘
   0       1        2         3       4        5
```

### Previous Structure
- **Home (0)**: Dashboard with statistics
- **Map (1)**: Interactive map with photo markers
- **Profiles (2)**: Standalone profiles management screen
- **Upload (3)**: Photo upload with camera/gallery
- **Log (4)**: Photo history and logs
- **Settings (5)**: App settings and preferences

---

## After: 5 Tabs

```
┌─────────────────────────────────────────────┐
│  Home  │  Map  │ Upload │  Log  │ Settings  │
└─────────────────────────────────────────────┘
   0       1        2       3        4
```

### New Structure
- **Home (0)**: Dashboard with statistics
- **Map (1)**: Interactive map with photo markers
- **Upload (2)**: Photo upload with camera/gallery
- **Log (3)**: Photo history and logs
- **Settings (4)**: App settings + Profile management

---

## Settings Screen Evolution

### Before
```
Settings Screen
├── User Profile Header
├── Account Section
├── Preferences Section
├── App Section
├── Support Section
└── Logout Button
```

### After
```
Settings Screen
├── User Profile Header
├── Profiles Section ⭐ NEW
│   ├── Add Profile Button
│   └── Profile List
│       ├── Profile Items (with Edit/Delete)
│       └── Empty State
├── Account Section
├── Preferences Section
├── App Section
├── Support Section
└── Logout Button
```

---

## Route Changes

### Removed Routes
```dart
// BEFORE
GoRoute(
  path: '/profiles',
  builder: (context, state) => const ProfilesScreenV2(),
),
```

### Updated Routes
```dart
// AFTER - Profiles route removed
// Profiles now accessible via Settings tab
```

---

## Navigation Flow

### Before
```
Home → Map → Profiles → Upload → Log → Settings
```

### After
```
Home → Map → Upload → Log → Settings (includes Profiles)
```

---

## Tab Index Changes

| Feature | Before | After | Change |
|---------|--------|-------|--------|
| Home | 0 | 0 | No change |
| Map | 1 | 1 | No change |
| Profiles | 2 | Settings | Moved to Settings |
| Upload | 3 | 2 | -1 |
| Log | 4 | 3 | -1 |
| Settings | 5 | 4 | -1 |

---

## Code Changes Summary

### Router (`app_router.dart`)
```diff
- import '../screens/profiles/profiles_screen_v2.dart';

  ShellRoute(
    routes: [
      GoRoute(path: '/home', ...),
      GoRoute(path: '/map', ...),
-     GoRoute(path: '/profiles', ...),
      GoRoute(path: '/upload', ...),
      GoRoute(path: '/log', ...),
      GoRoute(path: '/settings', ...),
    ],
  ),

  void _navigateToTab(int index) {
    switch (index) {
      case 0: context.go('/home'); break;
      case 1: context.go('/map'); break;
-     case 2: context.go('/profiles'); break;
-     case 3: context.go('/upload'); break;
-     case 4: context.go('/log'); break;
-     case 5: context.go('/settings'); break;
+     case 2: context.go('/upload'); break;
+     case 3: context.go('/log'); break;
+     case 4: context.go('/settings'); break;
    }
  }
```

### Bottom Navigation (`bottom_nav.dart`)
```diff
  List.generate(
-   6,
+   5,
    (index) => _buildNavItem(...),
  ),

  final items = [
    {'icon': Icons.home_outlined, 'label': 'Home'},
    {'icon': Icons.map_outlined, 'label': 'Map'},
-   {'icon': Icons.folder_outlined, 'label': 'Profiles'},
    {'icon': Icons.add_a_photo_outlined, 'label': 'Upload'},
    {'icon': Icons.history_outlined, 'label': 'Log'},
    {'icon': Icons.settings_outlined, 'label': 'Settings'},
  ];
```

### Settings Screen (`settings_screen_v2.dart`)
```diff
+ import '../../../data/models/profile_model.dart';
+ import '../../providers/profile_provider.dart';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeState = ref.watch(themeProvider);
+   final profilesAsync = ref.watch(profilesProvider);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User Profile Header
            ...
+           // Profiles Section ⭐ NEW
+           profilesAsync.when(
+             loading: () => ...,
+             error: (error, stack) => ...,
+             data: (profiles) => _buildProfilesSection(...),
+           ),
            // Account Section
            ...
          ],
        ),
      ),
    );
  }

+ Widget _buildProfilesSection(...) { ... }
+ Widget _buildProfileItem(...) { ... }
```

---

## Benefits

### 1. **Cleaner Navigation**
- Fewer tabs = less visual clutter
- Easier to navigate with one hand on mobile

### 2. **Logical Grouping**
- Profiles are settings/configuration
- Makes sense to group with other settings

### 3. **Improved UX**
- Settings is the last tab (easier to reach)
- Profiles accessible without extra navigation

### 4. **Consistent Design**
- Profiles section matches Settings design language
- Unified gray color scheme

### 5. **Better Space Utilization**
- Profiles integrated into existing screen
- No redundant navigation

---

## Backward Compatibility

### Breaking Changes
- `/profiles` route no longer exists
- Direct navigation to profiles must use `/settings`

### Migration Path
```dart
// OLD
context.push('/profiles');

// NEW
context.push('/settings');
// Then scroll to Profiles section
```

---

## Performance Impact

### Positive
- One less screen to load
- Reduced memory footprint
- Faster navigation

### Neutral
- Profiles data loaded with Settings
- No performance degradation

---

## Accessibility

### Improved
- Fewer tabs to navigate
- Clearer information hierarchy
- Consistent design patterns

### Maintained
- All existing accessibility features preserved
- Touch targets remain adequate

---

## Testing Recommendations

1. **Navigation**
   - [ ] Test all 5 tab navigation
   - [ ] Verify tab indices are correct
   - [ ] Test deep linking to settings

2. **Profiles Section**
   - [ ] Verify profiles load correctly
   - [ ] Test Add/Edit/Delete actions
   - [ ] Test empty state

3. **Settings**
   - [ ] Verify all settings still work
   - [ ] Test scrolling with profiles section
   - [ ] Test dark mode toggle
   - [ ] Test accent color picker

4. **Overall**
   - [ ] Test on different screen sizes
   - [ ] Test on iOS and Android
   - [ ] Verify no regressions

---

## Rollback Plan

If needed to revert:
1. Restore `/profiles` route in router
2. Restore Profiles tab in bottom navigation
3. Remove profiles section from Settings screen
4. Update tab indices back to original

---

**Status**: ✅ Complete
**Date**: May 12, 2026
**Version**: 1.0.0
