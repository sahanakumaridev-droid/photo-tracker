# Map View - Search Bar with Filter Icon Update

## Overview
Updated the Map View screen to feature a search bar with a filter icon dropdown menu instead of showing all profile chips.

## Changes Made

### 1. **Search Bar with Filter Icon**
- **Search Input**: Text field with search icon and "Search profiles..." hint
- **Filter Icon**: Dropdown menu button (🎚️ tune icon) on the right
- **Clean Layout**: Compact, professional design
- **Single Row**: Search bar and filter icon in one row

### 2. **Filter Dropdown Menu**
The filter icon opens a popup menu with:
- **All Profiles** option (with apps icon)
- **Divider** separator
- **Individual Profiles** (with colored dots matching service type)
  - Rush = Red
  - Airport = Blue
  - Standard = Green

### 3. **UI Components**

#### Search Bar
```
┌─ 🔍 Search profiles...                    🎚️ ┐
└────────────────────────────────────────────────┘
```

- Search icon on the left
- Placeholder text: "Search profiles..."
- Filter icon on the right
- White background with shadow
- Rounded corners (12px)

#### Filter Menu
- Popup menu with all profiles
- Color-coded dots for service types
- "All Profiles" option at top
- Divider for visual separation
- Smooth animations

### 4. **Functionality**

**Search Bar**:
- Clears when a filter is selected
- Can be used for future search functionality
- Real-time updates

**Filter Icon**:
- Tap to open profile list
- Select a profile to filter map
- Shows all profiles with their service types
- "All Profiles" option to reset filter

### 5. **Code Changes**

**Added**:
- `_searchController` - TextEditingController for search input
- Search bar UI with filter icon
- PopupMenuButton for filter dropdown
- Profile color indicators in menu

**Removed**:
- Old filter chips row
- `_buildFilterChip()` method
- Horizontal scrolling profile list

## Visual Design

### Search Bar
- **Background**: White
- **Border**: None (shadow only)
- **Icons**: Gray (search and filter)
- **Text**: Gray placeholder
- **Radius**: 12px
- **Shadow**: Subtle drop shadow

### Filter Menu
- **Background**: Material default
- **Items**: Profile names with colored dots
- **Divider**: Visual separator
- **Icons**: Service type colors

## User Flow

1. **View Map**
   - Search bar visible at top
   - Filter icon on the right

2. **Search** (future feature)
   - Type in search bar
   - Real-time filtering

3. **Filter by Profile**
   - Tap filter icon (🎚️)
   - Select profile from menu
   - Map updates to show only that profile's photos
   - Search bar clears

4. **View All**
   - Tap filter icon
   - Select "All Profiles"
   - Map shows all geotagged photos

## Benefits

✅ **Cleaner UI** - No cluttered profile chips
✅ **Better UX** - Dropdown menu is more scalable
✅ **Search Ready** - Search bar ready for future search functionality
✅ **Professional** - Matches modern app design patterns
✅ **Accessible** - Clear labels and icons
✅ **Responsive** - Works on all screen sizes

## Technical Details

### Search Bar Implementation
```dart
TextField(
  controller: _searchController,
  decoration: InputDecoration(
    hintText: 'Search profiles...',
    prefixIcon: Icon(Icons.search_outlined),
    border: InputBorder.none,
  ),
)
```

### Filter Menu Implementation
```dart
PopupMenuButton<String>(
  onSelected: (value) {
    setState(() {
      _selectedProfile = value;
      _searchController.clear();
    });
  },
  itemBuilder: (context) => [
    // All Profiles option
    // Divider
    // Profile items with colors
  ],
  icon: Icon(Icons.tune_outlined),
)
```

## Testing

The updated map view is ready to test:

```bash
flutter run
```

Navigate to the **Map** tab to see:
- Search bar with filter icon
- Dropdown menu with profiles
- Color-coded service types
- Smooth filtering

## Future Enhancements

- Implement search functionality to filter profiles by name
- Add search history
- Add advanced filters (date range, service type, etc.)
- Add filter badges showing active filters
- Add clear filter button

## Notes

- Search bar is ready for future search implementation
- Filter icon uses Material PopupMenuButton
- Profile colors match service types (Rush, Airport, Standard)
- All profiles option resets to show all photos
- Search bar clears when a filter is applied
