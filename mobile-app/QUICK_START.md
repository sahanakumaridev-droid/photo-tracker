# Photo Tracker Mobile App - Quick Start Guide

## 🚀 Getting Started

### Prerequisites
- Flutter 3.x installed
- Dart SDK installed
- iOS: Xcode 14+ (for iOS development)
- Android: Android Studio + SDK (for Android development)

### Installation

1. **Navigate to project directory**
   ```bash
   cd photo-tracker/mobile-app
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   # iOS
   flutter run -d ios
   
   # Android
   flutter run -d android
   
   # Specific device
   flutter run -d <device_id>
   ```

---

## 📱 App Features Overview

### 1. **Login Screen**
- Email/password authentication
- Connects to server: `http://24.199.85.230`

### 2. **Home Screen**
- Dashboard with photo statistics
- Recent photos display
- Quick action buttons

### 3. **Map View** ⭐ NEW
- Interactive map with photo markers
- Gray color scheme (CartoDB Positron tiles)
- Search and filter by profile
- Zoom to all markers
- View photo details by tapping markers

### 4. **Upload Screen** ⭐ UPDATED
- **Camera**: Take photos directly
- **Gallery**: Select from device
- Auto-detect location (GPS)
- Add zip code and notes
- Select profile before upload

### 5. **Profiles Screen**
- View all profiles
- Create new profiles
- Edit profile details
- Delete profiles

### 6. **Log Screen**
- View photo history
- Filter by profile
- Edit photo metadata
- Delete photos

### 7. **Settings Screen** ⭐ REDESIGNED
- User profile header
- Account settings (Email, Password)
- Preferences (Dark Mode, Accent Color)
- App info (Version, Build, Cache)
- Support links
- Logout with confirmation

---

## 🎨 Color Scheme

The app uses a professional gray color scheme from the web app:

```
Background:  #F8FAFC (Light gray)
Border:      #E2E8F0 (Medium gray)
Text:        #475569 (Dark gray)
Subtle:      #94A3B8 (Subtle gray)
```

---

## 🔐 Permissions

### iOS (Already Configured)
- ✅ Camera access
- ✅ Photo library access
- ✅ Location access

### Android (Needs Configuration)
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

---

## 🗺️ Map View Usage

### Features
1. **Search Bar**: Type to search profiles
2. **Filter Icon**: Click to select specific profile
3. **Markers**: Tap to view photo details
4. **Fit All**: Zoom to show all photos
5. **View List**: Switch to log view

### Marker Colors
- 🔴 **Red**: Rush service
- 🔵 **Blue**: Airport service
- 🟢 **Green**: Standard service

---

## 📸 Upload Flow

1. **Select Image**
   - Tap "Camera" to take a photo
   - Tap "Gallery" to select from device
   - Grant permissions when prompted

2. **Select Profile**
   - Choose profile from dropdown

3. **Location**
   - Auto-detected from GPS
   - Tap "Refresh Location" to update
   - Manually enter zip code if needed

4. **Add Details**
   - Optional: Add note about photo
   - Optional: Update zip code

5. **Upload**
   - Tap "Upload Photo"
   - Wait for confirmation

---

## ⚙️ Settings

### Account
- View email address
- Change password

### Preferences
- **Dark Mode**: Toggle dark theme
- **Accent Color**: Choose from Indigo, Purple, Blue, Green

### App
- View version (1.0.0)
- View build number (1)
- Clear app cache

### Support
- Help & Support
- Privacy Policy
- Terms of Service

### Logout
- Tap logout button
- Confirm logout
- Redirected to login screen

---

## 🧪 Testing

### Run Tests
```bash
# Run all tests
flutter test

# Run specific test
flutter test test/widget_test.dart

# Run with coverage
flutter test --coverage
```

### API Testing
```bash
# Run API tests
flutter test test/server_api_test.dart
```

---

## 🐛 Troubleshooting

### App Won't Start
1. Run `flutter clean`
2. Run `flutter pub get`
3. Run `flutter run`

### Permissions Not Working
1. Check Info.plist (iOS)
2. Check AndroidManifest.xml (Android)
3. Uninstall and reinstall app

### Location Not Detected
1. Enable location services on device
2. Grant location permission to app
3. Tap "Refresh Location" button

### Map Not Loading
1. Check internet connection
2. Verify server is running
3. Check server URL in `lib/config/app_config.dart`

### Upload Fails
1. Check image is selected
2. Check profile is selected
3. Check location is available
4. Check internet connection

---

## 📊 Project Structure

```
lib/
├── config/              # Configuration files
├── core/                # Core utilities
│   ├── network/         # API client
│   ├── storage/         # Local storage
│   └── utils/           # Utilities
├── data/                # Data layer
│   ├── models/          # Data models
│   └── repositories/    # Data repositories
└── presentation/        # UI layer
    ├── providers/       # Riverpod providers
    ├── router/          # Navigation
    ├── screens/         # App screens
    └── widgets/         # Reusable widgets
```

---

## 🔗 API Endpoints

### Base URL
```
http://24.199.85.230
```

### Key Endpoints
- `POST /auth/login` - Login
- `GET /profiles` - Get all profiles
- `POST /profiles` - Create profile
- `GET /photos` - Get all photos
- `POST /upload` - Upload photo
- `GET /logs` - Get photo logs

---

## 📝 Environment Variables

Create `.env` file (if needed):
```
SERVER_URL=http://24.199.85.230
API_TIMEOUT=30
```

---

## 🚢 Building for Release

### iOS
```bash
flutter build ios --release
```

### Android
```bash
flutter build apk --release
# or
flutter build appbundle --release
```

---

## 📞 Support

### Documentation
- `PROJECT_STATUS.md` - Full project status
- `VERIFICATION_CHECKLIST.md` - Verification checklist
- `API_TESTING_GUIDE.md` - API testing guide

### Key Files
- Settings: `lib/presentation/screens/settings/settings_screen_v2.dart`
- Map: `lib/presentation/screens/home/map_view_screen.dart`
- Upload: `lib/presentation/screens/upload/upload_screen_v2.dart`

---

## ✨ Recent Updates

### Settings Screen
- ✅ Modern USA UI/UX design
- ✅ Fixed icon and property errors
- ✅ All diagnostics passing

### Map View
- ✅ Gray color scheme applied
- ✅ Search and filter functionality
- ✅ Professional CartoDB tiles

### Upload Screen
- ✅ Camera and Gallery buttons
- ✅ Permission handling
- ✅ Gray color scheme

---

**Last Updated**: May 12, 2026
**Version**: 1.0.0
**Status**: ✅ Ready for Testing
