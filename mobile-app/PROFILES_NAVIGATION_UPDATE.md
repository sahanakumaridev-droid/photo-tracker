# Profiles Navigation Update

## Summary
The Profiles section in Settings has been updated to show a simple list of profiles. When users tap "Add Profile" or a profile item, they navigate to a dedicated Profiles Management screen for adding/editing profiles.

---

## Changes Made

### 1. **New Profiles Management Screen** ✅
**File**: `lib/presentation/screens/settings/profiles_management_screen.dart`

**Features**:
- Dedicated screen for adding and editing profiles
- Profile name input field
- Service type dropdown (Standard, Rush, Airport)
- Optional note field
- Create/Update button
- Cancel button
- Loading state during save
- Success/error notifications
- Gray color scheme matching app design

**Navigation**:
- Accessed via `/profiles-management` route
- Can pass existing profile via `extra` parameter for editing
- Returns to Settings after save/cancel

### 2. **Settings Screen Simplified** ✅
**File**: `lib/presentation/screens/settings/settings_screen_v2.dart`

**Changes**:
- Profiles section now shows simple list only
- "Add Profile" button navigates to management screen
- Tapping a profile navigates to management screen for editing
- Removed inline edit/delete dialogs
- Cleaner, simpler UI
- Removed unused dialog methods

**Profile List Display**:
- Service type color indicator
- Profile name
- Service type label
- Chevron indicator (shows it's clickable)
- Empty state message

### 3. **Router Updated** ✅
**File**: `lib/presentation/router/app_router.dart`

**Changes**:
- Added `/profiles-management` route
- Route accepts optional `ProfileModel` via `extra` parameter
- Route is outside ShellRoute (no bottom nav on management screen)
- Added ProfileModel import

---

## Navigation Flow

### Before
```
Settings Screen
├── Profiles Section (inline)
│   ├── Add Profile (dialog)
│   ├── Edit Profile (dialog)
│   └── Delete Profile (dialog)
└── Other Settings
```

### After
```
Settings Screen
├── Profiles Section (list only)
│   ├── Add Profile Button → /profiles-management (new profile)
│   └── Profile Item → /profiles-management (edit profile)
└── Other Settings

/profiles-management Screen
├── Profile Name Input
├── Service Type Dropdown
├── Note Field
├── Create/Update Button
└── Cancel Button
```

---

## Screen Details

### Profiles Management Screen

#### Add Profile Mode
```
┌─────────────────────────────────────┐
│  Add Profile                    ✕   │
├─────────────────────────────────────┤
│                                     │
│  Profile Name                       │
│  ┌─────────────────────────────────┐│
│  │ Enter profile name...           ││
│  └─────────────────────────────────┘│
│                                     │
│  Service Type                       │
│  ┌─────────────────────────────────┐│
│  │ ● Standard                      ││
│  │ ○ Rush                          ││
│  │ ○ Airport                       ││
│  └─────────────────────────────────┘│
│                                     │
│  Note (Optional)                    │
│  ┌─────────────────────────────────┐│
│  │ Add a note about this profile... ││
│  │                                 ││
│  │                                 ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌──────────────┐  ┌──────────────┐│
│  │ Create       │  │ Cancel       ││
│  │ Profile      │  │              ││
│  └──────────────┘  └──────────────┘│
│                                     │
└─────────────────────────────────────┘
```

#### Edit Profile Mode
```
┌─────────────────────────────────────┐
│  Edit Profile                   ✕   │
├─────────────────────────────────────┤
│                                     │
│  Profile Name                       │
│  ┌─────────────────────────────────┐│
│  │ John's Profile                  ││
│  └─────────────────────────────────┘│
│                                     │
│  Service Type                       │
│  ┌─────────────────────────────────┐│
│  │ ○ Standard                      ││
│  │ ● Rush                          ││
│  │ ○ Airport                       ││
│  └─────────────────────────────────┘│
│                                     │
│  Note (Optional)                    │
│  ┌─────────────────────────────────┐│
│  │ Rush service for urgent jobs    ││
│  │                                 ││
│  │                                 ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌──────────────┐  ┌──────────────┐│
│  │ Update       │  │ Cancel       ││
│  │ Profile      │  │              ││
│  └──────────────┘  └──────────────┘│
│                                     │
└─────────────────────────────────────┘
```

### Settings Screen - Profiles Section

```
┌─────────────────────────────────────┐
│ Profiles                      Add ▼  │
├─────────────────────────────────────┤
│                                     │
│ 🟢 John's Profile                   │
│    Rush service                  >  │
│                                     │
│ 🔵 Airport Delivery                 │
│    Airport service               >  │
│                                     │
│ 🟢 Standard Service                 │
│    Standard service              >  │
│                                     │
└─────────────────────────────────────┘
```

---

## Code Quality

### Diagnostics Status
- ✅ Profiles Management Screen: No errors or warnings
- ✅ Settings Screen: No errors or warnings
- ✅ Router: No errors or warnings

### Compilation
- ✅ All files compile successfully
- ✅ No import errors
- ✅ No type errors

---

## User Experience

### Benefits
1. **Cleaner Settings Screen**: Profiles section is simpler and less cluttered
2. **Dedicated Management Screen**: Full-screen form for better UX
3. **Better Navigation**: Clear flow between viewing and editing
4. **Consistent Design**: Management screen matches app design language
5. **No Bottom Nav**: Management screen has full screen space

### User Flow
1. User opens Settings tab
2. Sees Profiles section with list of profiles
3. Taps "Add Profile" → navigates to management screen
4. Fills in profile details
5. Taps "Create Profile" → saves and returns to Settings
6. Or taps a profile → navigates to management screen for editing

---

## Route Configuration

```dart
// Add Profile
context.push('/profiles-management');

// Edit Profile
context.push(
  '/profiles-management',
  extra: profileModel,
);
```

---

## API Integration (TODO)

The management screen has placeholder comments for API calls:

```dart
if (widget.profileToEdit != null) {
  // TODO: Call update API
  // PATCH /profiles/{id}
} else {
  // TODO: Call create API
  // POST /profiles
}
```

These can be connected to actual API endpoints when ready.

---

## Testing Checklist

- [ ] Navigate to Settings tab
- [ ] Verify Profiles section displays
- [ ] Tap "Add Profile" button
- [ ] Verify management screen opens
- [ ] Fill in profile details
- [ ] Tap "Create Profile"
- [ ] Verify profile is added to list
- [ ] Tap a profile in list
- [ ] Verify management screen opens with profile data
- [ ] Edit profile details
- [ ] Tap "Update Profile"
- [ ] Verify profile is updated in list
- [ ] Tap "Cancel" button
- [ ] Verify returns to Settings without saving
- [ ] Test on iOS device
- [ ] Test on Android device

---

## Files Modified

1. **New**: `lib/presentation/screens/settings/profiles_management_screen.dart`
2. **Updated**: `lib/presentation/screens/settings/settings_screen_v2.dart`
3. **Updated**: `lib/presentation/router/app_router.dart`

---

## Future Enhancements

1. **Delete Profile**: Add delete functionality to management screen
2. **Profile Validation**: Add more validation for profile fields
3. **API Integration**: Connect to actual profile API endpoints
4. **Photo Count**: Display number of photos per profile
5. **Profile Sorting**: Allow sorting profiles by name or type
6. **Profile Search**: Add search functionality in Settings

---

## Rollback Instructions

If needed to revert:
1. Remove `/profiles-management` route from router
2. Delete `profiles_management_screen.dart`
3. Restore inline dialogs in Settings screen
4. Restore old dialog methods

---

**Status**: ✅ Complete and Ready for Testing
**Date**: May 12, 2026
**Version**: 1.0.0
