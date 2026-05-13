# Server API Testing Guide

## Quick Start

### Run All Server API Tests
```bash
flutter test test/server_api_test.dart -v
```

### Run Specific Test Group
```bash
flutter test test/server_api_test.dart -k "PROFILE ENDPOINTS" -v
```

### Run with Output
```bash
flutter test test/server_api_test.dart --verbose
```

---

## Server Configuration

**Server URL**: `http://24.199.85.230`

This is configured in `lib/config/app_config.dart`:
```dart
static const String apiBaseUrl = 'http://24.199.85.230';
```

---

## Test Coverage

### ✅ Profile Endpoints (5 tests)
- [x] GET /profiles - Fetch all profiles
- [x] POST /profiles - Create new profile
- [x] GET /profiles/{id}/photos - Fetch profile photos
- [x] PATCH /profiles/{id} - Update profile
- [x] DELETE /profiles/{id} - Delete profile

### ✅ Photo Endpoints (6 tests)
- [x] GET /photos - Fetch all photos
- [x] PATCH /photos/{id}/location - Update location
- [x] PATCH /photos/{id}/note - Update note
- [x] PATCH /photos/{id}/zip - Update zip code
- [x] PATCH /photos/{id}/profiles - Update profiles
- [x] DELETE /photos/{id} - Delete photo

### ✅ Log Endpoints (3 tests)
- [x] GET /log - Fetch activity log
- [x] GET /log (with filters) - Fetch filtered log
- [x] POST /export/email - Export log to email

### ⚠️ File Upload Endpoints (2 tests - pending)
- [ ] POST /upload - Upload photo
- [ ] PATCH /photos/{id}/image - Replace photo image

---

## What Gets Tested

### Connection Test
- Verifies server is reachable
- Checks response status code
- Validates API base URL

### Profile Tests
- Creates test profiles
- Fetches all profiles
- Updates profile data
- Deletes test profiles
- Retrieves profile photos

### Photo Tests
- Fetches all photos
- Updates photo metadata (location, note, zip)
- Updates photo profile associations
- Deletes photos

### Log Tests
- Fetches activity log
- Applies filters (zip code, status)
- Exports log to email

---

## Expected Output

When you run the tests, you'll see output like:

```
✅ SERVER CONNECTION - SUCCESS
   Server: http://24.199.85.230
   Status: 200

✅ GET /profiles
   Total profiles: 5
   • Profile 1 (standard) - ID: 1
   • Profile 2 (rush) - ID: 2
   ...

✅ POST /profiles
   Created: Test Profile 1234567890
   ID: 6
   Type: standard

✅ GET /photos
   Total photos: 12
   • Photo ID: 1
     Location: (32.7157, -117.1611)
     Profile: Profile 1
     Type: standard
   ...

✅ PATCH /photos/{id}/location
   Updated photo ID: 1
   New location: (32.7157, -117.1611)

...

🌐 SERVER API TEST SUMMARY
📍 Server: http://24.199.85.230
⏰ Tested at: 2024-05-12 10:30:45.123456

✅ WORKING ENDPOINTS: 12
⚠️  NEEDS TESTING: 2 (file upload)
📈 Total endpoints: 14
```

---

## Troubleshooting

### Connection Failed
**Error**: `Connection refused` or `Failed to connect`

**Solution**:
1. Verify server is running
2. Check server URL in `app_config.dart`
3. Verify network connectivity
4. Check firewall settings

### 404 Not Found
**Error**: `404 Not Found`

**Solution**:
1. Verify endpoint path is correct
2. Check resource ID exists
3. Review backend logs

### 422 Unprocessable Entity
**Error**: `422 Unprocessable Entity`

**Solution**:
1. Check request parameters
2. Verify data types
3. Ensure required fields are provided

### 500 Internal Server Error
**Error**: `500 Internal Server Error`

**Solution**:
1. Check backend logs
2. Verify database is accessible
3. Check file permissions

---

## Test Results Interpretation

### ✅ Green (Passing)
- Endpoint is working correctly
- Server responded with expected data
- No errors occurred

### ❌ Red (Failing)
- Endpoint returned an error
- Server is unreachable
- Data validation failed

### ⚠️ Yellow (Skipped)
- Test was skipped due to missing data
- No profiles/photos available to test with
- Not a failure, just couldn't run test

---

## Manual Testing with curl

### Test GET /profiles
```bash
curl http://24.199.85.230/profiles
```

### Test POST /profiles
```bash
curl -X POST http://24.199.85.230/profiles \
  -F "name=Test Profile" \
  -F "service_type=standard"
```

### Test GET /photos
```bash
curl http://24.199.85.230/photos
```

### Test GET /log
```bash
curl "http://24.199.85.230/log?zip_code=92&status=standard"
```

---

## Performance Notes

### Typical Response Times
- GET /profiles: 50-100ms
- GET /photos: 100-200ms (depends on photo count)
- POST /profiles: 100-150ms
- PATCH endpoints: 50-100ms
- DELETE endpoints: 100-200ms

### Factors Affecting Performance
- Network latency
- Server load
- Database size
- File upload size

---

## Next Steps

### 1. Run Tests
```bash
flutter test test/server_api_test.dart -v
```

### 2. Review Results
- Check which endpoints are working
- Identify any failures
- Note any warnings

### 3. Test File Upload
- Manually test POST /upload
- Manually test PATCH /photos/{id}/image
- Verify file storage

### 4. Integration Testing
- Test full upload flow in app
- Test image picker integration
- Test permission handling

---

## API Endpoints Reference

| Endpoint | Method | Status |
|----------|--------|--------|
| /profiles | GET | ✅ |
| /profiles | POST | ✅ |
| /profiles/{id} | PATCH | ✅ |
| /profiles/{id} | DELETE | ✅ |
| /profiles/{id}/photos | GET | ✅ |
| /photos | GET | ✅ |
| /upload | POST | ⚠️ |
| /photos/{id}/location | PATCH | ✅ |
| /photos/{id}/note | PATCH | ✅ |
| /photos/{id}/zip | PATCH | ✅ |
| /photos/{id}/profiles | PATCH | ✅ |
| /photos/{id}/image | PATCH | ⚠️ |
| /photos/{id} | DELETE | ✅ |
| /log | GET | ✅ |
| /export/email | POST | ✅ |

---

## Support

For issues:
1. Check server logs
2. Verify network connectivity
3. Review error messages
4. Check API documentation

For questions:
1. Review this guide
2. Check API_TESTING_GUIDE.md
3. Review API_TEST_RESULTS.md
