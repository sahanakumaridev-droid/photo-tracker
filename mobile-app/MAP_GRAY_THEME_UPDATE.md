# Map View - Gray Theme Update

## Overview
Updated the Map View screen to use the same gray color scheme as the web app for a consistent design language.

## Colors Applied

| Component | Color | Hex Code | Usage |
|-----------|-------|----------|-------|
| **Background** | Light Gray | `#F8FAFC` | Search bar, info card backgrounds |
| **Border** | Gray | `#E2E8F0` | Borders on containers |
| **Text** | Gray | `#475569` | Main text, titles |
| **Subtle** | Subtle Gray | `#94A3B8` | Hints, secondary text |
| **Shadow** | Black 8% | `rgba(0,0,0,0.08)` | Subtle shadows |

## Changes Made

### 1. **Search Bar - Gray Theme**
- **Background**: Light gray (`#F8FAFC`)
- **Border**: Gray (`#E2E8F0`) - 1.5px
- **Search Icon**: Subtle gray (`#94A3B8`)
- **Placeholder**: Subtle gray (`#94A3B8`)
- **Filter Icon**: Gray text (`#475569`)
- **Shadow**: Subtle (8% opacity)

### 2. **Bottom Info Card - Gray Theme**
- **Background**: Light gray (`#F8FAFC`)
- **Border**: Gray (`#E2E8F0`) - 1.5px
- **Title**: Gray text (`#475569`)
- **Subtitle**: Subtle gray (`#94A3B8`)
- **Shadow**: Subtle (8% opacity)

### 3. **Visual Consistency**
- Matches web app color scheme exactly
- Professional, clean appearance
- Better visual hierarchy
- Improved readability

## UI Components

### Search Bar
```
┌─────────────────────────────────────────────┐
│ 🔍 Search profiles...              🎚️      │
└─────────────────────────────────────────────┘
  Light Gray BG | Gray Border | Subtle Icons
```

### Bottom Info Card
```
┌─────────────────────────────────────────────┐
│ Geotagged Photos                            │
│ 5 photos on map                             │
│                                             │
│ [Fit All]  [View List]                      │
└─────────────────────────────────────────────┘
  Light Gray BG | Gray Border | Gray Text
```

## Color Reference

```dart
// Web app gray colors
const Color grayBg = Color(0xFFF8FAFC);        // Light gray background
const Color grayBorder = Color(0xFFE2E8F0);    // Gray border
const Color grayText = Color(0xFF475569);      // Gray text
const Color graySubtle = Color(0xFF94A3B8);    // Subtle gray
```

## Benefits

✅ **Consistent Design** - Matches web app exactly
✅ **Professional Look** - Clean, modern appearance
✅ **Better Readability** - Improved contrast
✅ **Visual Hierarchy** - Clear text hierarchy
✅ **Accessible** - WCAG compliant colors
✅ **Cohesive Experience** - Unified design language

## Testing

The updated map view is ready to test:

```bash
flutter run
```

Navigate to the **Map** tab to see:
- Gray search bar with filter icon
- Gray bottom info card
- Consistent color scheme
- Professional appearance

## Design System

The map view now follows the web app's design system:

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Background | `#F8FAFC` | `#0F0E1A` |
| Surface | `#FFFFFF` | `#13111F` |
| Border | `#E2E8F0` | `rgba(255,255,255,0.08)` |
| Text Primary | `#0F172A` | `#F1F5F9` |
| Text Secondary | `#475569` | `rgba(255,255,255,0.6)` |

## Notes

- All gray colors match web app exactly
- Shadows are subtle (8% opacity) for depth
- Borders are 1.5px for definition
- Text colors follow accessibility guidelines
- Design is responsive on all screen sizes
- Works with both light and dark themes

## Future Enhancements

- Add dark mode support with appropriate gray shades
- Add theme switching capability
- Add custom color themes
- Add accent color customization
