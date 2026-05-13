# API Testing Guide

## Overview
Complete guide to test all APIs in the Photo Tracker mobile app.

## Prerequisites

1. **Backend Running**
   ```bash
   cd backend
   python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

2. **Update API Base URL**
   - Edit `lib/config/app_config.dart`
   - Set `apiBaseUrl` to your backend URL (e.g., `http://localhost:8000`)

3. **Run Tests**
   ```bash
   flutter test test/api_test.dart
   ```

## API Endpoints

### Profile Endpoints

#### 1. GET /profiles
**Purpose**: Get all profiles
**Status**: ✅ WORKING

```dart
final profiles = await apiService.getProfiles();
```

**Expected Response**:
```json
[
  {
    "id": 1,
    "name": "Profile Name",
    "service_type": "standard",
    "note": "Optional note"
  }
]
```

**Test**:
```bash
curl http://localhost:8000/profiles
```

---

#### 2. POST /profiles
**Purpose**: Create a new profile
**Status**: ✅ WORKING

```dart
final profile = await apiService.createProfile(
  name: 'New Profile',
  serviceType: 'standard', // or 'rush', 'airport'
);
```

**Expected Response**:
```json
{
  "id": 2,
  "name": "New Profile",
  "service_type": "standard"
}
```

**Test**:
```bash
curl -X POST http://localhost:8000/profiles \
  -F "name=Test Profile" \
  -F "service_type=standard"
```

---

#### 3. PATCH /profiles/{id}
**Purpose**: Update a profile
**Status**: ✅ WORKING

```dart
await apiService.updateProfile(
  profileId: 1,
  name: 'Updated Name',
  serviceType: 'rush',
  note: 'Updated note',
);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/profiles/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Updated","service_type":"rush"}'
```

---

#### 4. GET /profiles/{id}/photos
**Purpose**: Get all photos for a profile
**Status**: ✅ WORKING

```dart
final profilePhotos = await apiService.getProfilePhotos(1);
```

**Expected Response**:
```json
{
  "profile": {
    "id": 1,
    "name": "Profile Name",
    "service_type": "standard"
  },
  "photos": [
    {
      "id": 1,
      "image_url": "/uploads/...",
      "latitude": 32.7157,
      "longitude": -117.1611
    }
  ]
}
```

**Test**:
```bash
curl http://localhost:8000/profiles/1/photos
```

---

#### 5. DELETE /profiles/{id}
**Purpose**: Delete a profile
**Status**: ✅ WORKING

```dart
await apiService.deleteProfile(1);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X DELETE http://localhost:8000/profiles/1
```

---

### Photo Endpoints

#### 1. GET /photos
**Purpose**: Get all photos
**Status**: ✅ WORKING

```dart
final photos = await apiService.getPhotos();
```

**Expected Response**:
```json
[
  {
    "id": 1,
    "image_url": "/uploads/...",
    "timestamp": "2024-05-12T10:30:00-07:00",
    "latitude": 32.7157,
    "longitude": -117.1611,
    "zip_code": "92101",
    "note": "Photo note",
    "profile_id": 1,
    "profile_name": "Profile Name",
    "service_type": "standard",
    "profiles": [...]
  }
]
```

**Test**:
```bash
curl http://localhost:8000/photos
```

---

#### 2. POST /upload
**Purpose**: Upload a new photo
**Status**: ⚠️ NEEDS TESTING (File Upload)

```dart
final photo = await apiService.uploadPhoto(
  filePath: '/path/to/image.jpg',
  profileId: 1,
  latitude: 32.7157,
  longitude: -117.1611,
  zipCode: '92101',
  note: 'Photo note',
);
```

**Expected Response**:
```json
{
  "id": 2,
  "image_url": "/uploads/...",
  "timestamp": "2024-05-12T10:30:00-07:00",
  "latitude": 32.7157,
  "longitude": -117.1611,
  "zip_code": "92101",
  "note": "Photo note",
  "profile_id": 1,
  "profile_name": "Profile Name",
  "service_type": "standard"
}
```

**Test**:
```bash
curl -X POST http://localhost:8000/upload \
  -F "file=@/path/to/image.jpg" \
  -F "profile_id=1" \
  -F "latitude=32.7157" \
  -F "longitude=-117.1611" \
  -F "zip_code=92101" \
  -F "note=Test photo"
```

---

#### 3. PATCH /photos/{id}/location
**Purpose**: Update photo location
**Status**: ✅ WORKING

```dart
await apiService.updatePhotoLocation(
  photoId: 1,
  latitude: 32.7157,
  longitude: -117.1611,
);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/photos/1/location \
  -H "Content-Type: application/json" \
  -d '{"latitude":32.7157,"longitude":-117.1611}'
```

---

#### 4. PATCH /photos/{id}/note
**Purpose**: Update photo note
**Status**: ✅ WORKING

```dart
await apiService.updatePhotoNote(
  photoId: 1,
  note: 'Updated note',
);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/photos/1/note \
  -H "Content-Type: application/json" \
  -d '{"note":"Updated note"}'
```

---

#### 5. PATCH /photos/{id}/zip
**Purpose**: Update photo zip code
**Status**: ✅ WORKING

```dart
await apiService.updatePhotoZip(
  photoId: 1,
  zipCode: '92101',
);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/photos/1/zip \
  -H "Content-Type: application/json" \
  -d '{"zip_code":"92101"}'
```

---

#### 6. PATCH /photos/{id}/profiles
**Purpose**: Update photo profiles
**Status**: ✅ WORKING

```dart
await apiService.updatePhotoProfiles(
  photoId: 1,
  profileIds: [1, 2, 3],
);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/photos/1/profiles \
  -H "Content-Type: application/json" \
  -d '{"profile_ids":[1,2,3]}'
```

---

#### 7. PATCH /photos/{id}/image
**Purpose**: Replace photo image
**Status**: ⚠️ NEEDS TESTING (File Upload)

```dart
final photo = await apiService.replacePhotoImage(
  photoId: 1,
  filePath: '/path/to/new_image.jpg',
);
```

**Expected Response**:
```json
{
  "id": 1,
  "image_url": "/uploads/...",
  "timestamp": "2024-05-12T10:30:00-07:00",
  "latitude": 32.7157,
  "longitude": -117.1611
}
```

**Test**:
```bash
curl -X PATCH http://localhost:8000/photos/1/image \
  -F "file=@/path/to/new_image.jpg"
```

---

#### 8. DELETE /photos/{id}
**Purpose**: Delete a photo
**Status**: ✅ WORKING

```dart
await apiService.deletePhoto(1);
```

**Expected Response**:
```json
{
  "ok": true
}
```

**Test**:
```bash
curl -X DELETE http://localhost:8000/photos/1
```

---

### Log Endpoints

#### 1. GET /log
**Purpose**: Get activity log
**Status**: ✅ WORKING

```dart
final logs = await apiService.getLog();
```

**With Filters**:
```dart
final logs = await apiService.getLog(
  date: '2024-05-12',
  zipCode: '92101',
  status: 'standard',
  search: 'keyword',
);
```

**Expected Response**:
```json
[
  {
    "id": 1,
    "image_url": "/uploads/...",
    "timestamp": "2024-05-12T10:30:00-07:00",
    "latitude": 32.7157,
    "longitude": -117.1611,
    "zip_code": "92101",
    "note": "Photo note",
    "profile_id": 1,
    "profile_name": "Profile Name",
    "service_type": "standard"
  }
]
```

**Test**:
```bash
curl "http://localhost:8000/log?date=2024-05-12&zip_code=92101"
```

---

#### 2. POST /export/email
**Purpose**: Export log to email
**Status**: ✅ WORKING (if SMTP configured)

```dart
await apiService.exportLogEmail(
  email: 'user@example.com',
  records: logs.map((l) => l.toJson()).toList(),
);
```

**Expected Response**:
```json
{
  "ok": true,
  "message": "Log exported to user@example.com",
  "count": 5
}
```

**Test**:
```bash
curl -X POST http://localhost:8000/export/email \
  -H "Content-Type: application/json" \
  -d '{
    "to": "user@example.com",
    "records": [...]
  }'
```

---

## API Status Summary

### ✅ WORKING (Tested & Verified)
- GET /profiles
- POST /profiles
- PATCH /profiles/{id}
- GET /profiles/{id}/photos
- DELETE /profiles/{id}
- GET /photos
- PATCH /photos/{id}/location
- PATCH /photos/{id}/note
- PATCH /photos/{id}/zip
- PATCH /photos/{id}/profiles
- DELETE /photos/{id}
- GET /log
- GET /log (with filters)
- POST /export/email

### ⚠️ NEEDS TESTING (File Upload)
- POST /upload
- PATCH /photos/{id}/image

## Running Tests

### Run All API Tests
```bash
flutter test test/api_test.dart -v
```

### Run Specific Test
```bash
flutter test test/api_test.dart -k "GET /profiles"
```

### Run with Output
```bash
flutter test test/api_test.dart --verbose
```

## Troubleshooting

### Connection Refused
- Ensure backend is running on correct port
- Check firewall settings
- Verify API base URL in app_config.dart

### 404 Not Found
- Check endpoint path is correct
- Verify resource ID exists
- Check backend logs

### 422 Unprocessable Entity
- Validate request parameters
- Check data types match expected
- Verify required fields are provided

### 500 Internal Server Error
- Check backend logs
- Verify database is accessible
- Check file upload permissions

## Notes

- All timestamps are in PST (Pacific Standard Time)
- Coordinates must be valid (lat: -90 to 90, lng: -180 to 180)
- File uploads require multipart/form-data
- Email export requires SMTP configuration
- All endpoints return JSON responses
