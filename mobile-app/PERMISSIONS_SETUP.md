# Camera & Gallery Permissions Setup

## Overview
The upload screen now requests camera and gallery permissions before allowing users to pick images.

## Implementation

### 1. **Permission Requests**

The app now requests permissions when users tap Camera or Gallery buttons:

**Camera Permission**
- Requested when user taps "Camera" button
- Shows error message if permission is denied
- Allows user to take photos directly

**Gallery Permission**
- Requested when user taps "Gallery" button
- Shows error message if permission is denied
- Allows user to select photos from device

### 2. **Code Implementation**

```dart
Future<void> _pickImage(ImageSource source) async {
  try {
    // Request permissions based on source
    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        // Show error message
        return;
      }
    } else if (source == ImageSource.gallery) {
      final photoStatus = await Permission.photos.request();
      if (!photoStatus.isGranted) {
        // Show error message
        return;
      }
    }
    
    // Pick image after permission granted
    final pickedFile = await _imagePicker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
    }
  } catch (e) {
    // Handle errors
  }
}
```

## iOS Configuration

### Info.plist Permissions

Add the following keys to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to your camera to take photos for geotagging.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to your photo library to select photos for geotagging.</string>

<key>NSPhotoLibraryAddOnlyUsageDescription</key>
<string>This app needs permission to save photos to your library.</string>
```

**Status**: ✅ Already configured in Info.plist

## Android Configuration

### AndroidManifest.xml Permissions

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

### Android 13+ (API 33+)

For Android 13 and above, add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

### build.gradle Configuration

Ensure `android/app/build.gradle` has:

```gradle
android {
    compileSdkVersion 34  // or higher
    
    defaultConfig {
        targetSdkVersion 34  // or higher
    }
}
```

## Permission Handler Package

The app uses `permission_handler: ^11.4.0` which is already in pubspec.yaml.

### Supported Permissions

- `Permission.camera` - Camera access
- `Permission.photos` - Photo library access
- `Permission.storage` - File storage access

## User Experience

### Camera Flow
1. User taps "Camera" button
2. Permission dialog appears (first time only)
3. User grants permission
4. Camera app opens
5. User takes photo
6. Photo appears in preview

### Gallery Flow
1. User taps "Gallery" button
2. Permission dialog appears (first time only)
3. User grants permission
4. Gallery picker opens
5. User selects photo
6. Photo appears in preview

### Permission Denied
- Shows SnackBar message
- Explains why permission is needed
- User can retry or use settings to grant permission

## Error Messages

**Camera Permission Denied**
```
"Camera permission is required to take photos"
```

**Gallery Permission Denied**
```
"Gallery permission is required to select photos"
```

## Testing

### iOS Testing
1. Run app on iOS device or simulator
2. Tap "Camera" button
3. Grant camera permission when prompted
4. Take a photo
5. Tap "Gallery" button
6. Grant photo library permission when prompted
7. Select a photo

### Android Testing
1. Run app on Android device or emulator
2. Tap "Camera" button
3. Grant camera permission when prompted
4. Take a photo
5. Tap "Gallery" button
6. Grant photo library permission when prompted
7. Select a photo

## Troubleshooting

### iOS Issues

**Permission dialog not appearing**
- Check Info.plist has all three permission keys
- Restart the app
- Clear app cache and reinstall

**Camera not working**
- Ensure device has camera hardware
- Check camera is not in use by another app
- Restart device

### Android Issues

**Permission dialog not appearing**
- Check AndroidManifest.xml has all permissions
- Ensure targetSdkVersion is 33 or higher
- Restart the app

**Gallery not opening**
- Check READ_EXTERNAL_STORAGE permission
- For Android 13+, check READ_MEDIA_IMAGES permission
- Restart device

## Platform-Specific Notes

### iOS
- Permissions are requested at runtime (iOS 10+)
- Users can change permissions in Settings > Privacy
- Camera permission is required for camera access
- Photo library permission is required for gallery access

### Android
- Permissions are requested at runtime (Android 6.0+)
- Users can change permissions in Settings > Apps > Permissions
- Multiple permissions can be requested together
- Android 13+ requires READ_MEDIA_IMAGES instead of READ_EXTERNAL_STORAGE

## Security Considerations

✅ Permissions are only requested when needed
✅ Users can deny permissions and still use the app
✅ Permissions are handled gracefully with error messages
✅ No sensitive data is accessed without permission
✅ Follows platform best practices

## References

- [permission_handler package](https://pub.dev/packages/permission_handler)
- [iOS Privacy Permissions](https://developer.apple.com/documentation/bundleresources/information_property_list/privacy_-_camera_usage_description)
- [Android Permissions](https://developer.android.com/guide/topics/permissions/overview)
- [Flutter Image Picker](https://pub.dev/packages/image_picker)

## Checklist

- [x] Add permission_handler to pubspec.yaml
- [x] Add iOS permissions to Info.plist
- [ ] Add Android permissions to AndroidManifest.xml
- [ ] Test on iOS device
- [ ] Test on Android device
- [ ] Verify permission dialogs appear
- [ ] Verify camera works
- [ ] Verify gallery works
- [ ] Test permission denial flow
