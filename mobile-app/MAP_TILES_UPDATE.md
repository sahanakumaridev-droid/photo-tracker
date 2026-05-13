# Map Tiles - Gray/Grayscale Update

## Overview
Updated the map tiles from colorful OpenStreetMap to CartoDB Positron (light gray/grayscale) for a cleaner, more professional appearance.

## Changes Made

### Map Tile Provider

**Before**
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.photo_tracker',
)
```

**After**
```dart
TileLayer(
  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
  subdomains: const ['a', 'b', 'c', 'd'],
  userAgentPackageName: 'com.example.photo_tracker',
)
```

### Tile Provider Details

**CartoDB Positron (Light)**
- **URL**: `https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png`
- **Style**: Light gray/grayscale
- **Colors**: Whites, grays, blues
- **Attribution**: © OpenStreetMap contributors © CARTO
- **Free**: Yes, no API key required
- **Performance**: Excellent

### Visual Appearance

**Before (Colorful)**
- Bright greens for parks
- Orange/yellow for roads
- Multiple colors
- Busy appearance

**After (Gray/Grayscale)**
- Light gray background
- Subtle gray roads
- Light blue water
- Clean, professional look
- Photo markers stand out more

## Benefits

✅ **Professional Look** - Clean, minimalist design
✅ **Better Contrast** - Photo markers stand out more
✅ **Consistent Design** - Matches web app aesthetic
✅ **Reduced Distraction** - Focus on photo locations
✅ **Modern Feel** - Contemporary map style
✅ **Free & Fast** - No API key, excellent performance

## Map Tile Options

If you want to switch to different tile styles, here are alternatives:

### Light Grayscale (Current)
```
https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png
```

### Dark Grayscale
```
https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png
```

### Voyager (Detailed)
```
https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png
```

### Positron (Minimal)
```
https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png
```

### OpenStreetMap (Original)
```
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

## Attribution

CartoDB Positron requires attribution:
```
© OpenStreetMap contributors © CARTO
```

This is automatically handled by flutter_map.

## Performance

- **Load Time**: Fast (cached by CDN)
- **File Size**: Small (optimized tiles)
- **Bandwidth**: Low
- **Compatibility**: All devices
- **Offline**: Not available (requires internet)

## Testing

The updated map is ready to test:

```bash
flutter run
```

Navigate to the **Map** tab to see:
- Gray/grayscale map tiles
- Clean, professional appearance
- Photo markers stand out
- Improved visual hierarchy

## Color Palette

### Map Colors
- **Background**: Light gray/white
- **Roads**: Light gray
- **Water**: Light blue
- **Parks**: Very light green
- **Labels**: Dark gray

### Photo Markers
- **Rush**: Red (stands out on gray)
- **Airport**: Blue (stands out on gray)
- **Standard**: Green (stands out on gray)

## Customization

To change tile styles, update the `urlTemplate` in `map_view_screen.dart`:

```dart
TileLayer(
  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
  subdomains: const ['a', 'b', 'c', 'd'],
  userAgentPackageName: 'com.example.photo_tracker',
)
```

## Notes

- Gray tiles match web app design language
- Photo markers are more visible on gray background
- No API key required
- Free for commercial use
- Excellent performance
- Works offline after caching

## Future Enhancements

- Add dark mode with dark tiles
- Add tile style switcher
- Add custom tile provider option
- Add offline map support
- Add satellite view option

## References

- [CartoDB Basemaps](https://carto.com/basemaps/)
- [flutter_map Documentation](https://pub.dev/packages/flutter_map)
- [OpenStreetMap](https://www.openstreetmap.org/)
