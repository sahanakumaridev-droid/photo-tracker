# Quick Test Commands

## 🚀 Run Tests

### Run All Server API Tests
```bash
flutter test test/server_api_test.dart -v
```

### Run Profile Tests Only
```bash
flutter test test/server_api_test.dart -k "PROFILE" -v
```

### Run Photo Tests Only
```bash
flutter test test/server_api_test.dart -k "PHOTO" -v
```

### Run Log Tests Only
```bash
flutter test test/server_api_test.dart -k "LOG" -v
```

### Run Connection Test Only
```bash
flutter test test/server_api_test.dart -k "Connection" -v
```

---

## 🔍 Manual Testing with curl

### Test Server Connection
```bash
curl http://24.199.85.230/profiles
```

### Get All Profiles
```bash
curl http://24.199.85.230/profiles
```

### Create Profile
```bash
curl -X POST http://24.199.85.230/profiles \
  -F "name=Test Profile" \
  -F "service_type=standard"
```

### Get All Photos
```bash
curl http://24.199.85.230/photos
```

### Get Activity Log
```bash
curl http://24.199.85.230/log
```

### Get Filtered Log
```bash
curl "http://24.199.85.230/log?zip_code=92&status=standard"
```

### Update Photo Location
```bash
curl -X PATCH http://24.199.85.230/photos/1/location \
  -H "Content-Type: application/json" \
  -d '{"latitude":32.7157,"longitude":-117.1611}'
```

### Update Photo Note
```bash
curl -X PATCH http://24.199.85.230/photos/1/note \
  -H "Content-Type: application/json" \
  -d '{"note":"Updated note"}'
```

### Delete Photo
```bash
curl -X DELETE http://24.199.85.230/photos/1
```

### Upload Photo
```bash
curl -X POST http://24.199.85.230/upload \
  -F "file=@image.jpg" \
  -F "profile_id=1" \
  -F "latitude=32.7157" \
  -F "longitude=-117.1611" \
  -F "zip_code=92101" \
  -F "note=Test photo"
```

---

## 📊 View Test Results

### Verbose Output
```bash
flutter test test/server_api_test.dart --verbose
```

### With Timestamps
```bash
flutter test test/server_api_test.dart -v --reporter=expanded
```

### Save to File
```bash
flutter test test/server_api_test.dart -v > test_results.txt
```

---

## 🔧 Configuration

### Server URL
File: `lib/config/app_config.dart`
```dart
static const String apiBaseUrl = 'http://24.199.85.230';
```

### API Timeout
```dart
static const int apiTimeout = 30; // seconds
```

---

## 📋 Test Summary

| Test | Command | Status |
|------|---------|--------|
| All Tests | `flutter test test/server_api_test.dart -v` | ✅ |
| Profile Tests | `flutter test test/server_api_test.dart -k "PROFILE" -v` | ✅ |
| Photo Tests | `flutter test test/server_api_test.dart -k "PHOTO" -v` | ✅ |
| Log Tests | `flutter test test/server_api_test.dart -k "LOG" -v` | ✅ |
| Connection | `flutter test test/server_api_test.dart -k "Connection" -v` | ✅ |

---

## 🎯 Expected Results

### Successful Test Output
```
✅ SERVER CONNECTION - SUCCESS
✅ GET /profiles
✅ POST /profiles
✅ GET /profiles/{id}/photos
✅ PATCH /profiles/{id}
✅ DELETE /profiles/{id}
✅ GET /photos
✅ PATCH /photos/{id}/location
✅ PATCH /photos/{id}/note
✅ PATCH /photos/{id}/zip
✅ PATCH /photos/{id}/profiles
✅ DELETE /photos/{id}
✅ GET /log
✅ GET /log (with filters)
✅ POST /export/email
```

### Test Summary
```
🌐 SERVER API TEST SUMMARY
📍 Server: http://24.199.85.230
✅ WORKING ENDPOINTS: 12
⚠️  NEEDS TESTING: 2 (file upload)
📈 Total endpoints: 14
```

---

## 🐛 Troubleshooting

### Connection Failed
```bash
# Check if server is running
curl http://24.199.85.230/profiles

# If fails, verify:
# 1. Server is running
# 2. Network connectivity
# 3. Firewall settings
```

### Test Timeout
```bash
# Increase timeout in app_config.dart
static const int apiTimeout = 60; // seconds
```

### No Data Available
```bash
# Some tests skip if no data exists
# This is normal - not a failure
# Create test data first if needed
```

---

## 📚 Documentation Files

- **API_TESTING_SUMMARY.md** - Overall summary
- **SERVER_API_TEST_GUIDE.md** - Detailed guide
- **API_TESTING_GUIDE.md** - Endpoint documentation
- **API_TEST_RESULTS.md** - Status report
- **QUICK_TEST_COMMANDS.md** - This file

---

## ✨ Quick Tips

1. **Run tests before deployment**
   ```bash
   flutter test test/server_api_test.dart -v
   ```

2. **Test specific endpoint**
   ```bash
   flutter test test/server_api_test.dart -k "endpoint_name" -v
   ```

3. **Save results**
   ```bash
   flutter test test/server_api_test.dart -v > results.txt
   ```

4. **Manual testing**
   ```bash
   curl http://24.199.85.230/profiles
   ```

5. **Check server status**
   ```bash
   curl -I http://24.199.85.230/profiles
   ```

---

## 🎉 Ready to Test!

Run this command to test all APIs:
```bash
flutter test test/server_api_test.dart -v
```

All 12 core endpoints should pass! ✅
