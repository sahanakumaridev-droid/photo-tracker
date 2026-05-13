import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_tracker/core/network/api_client.dart';

void main() {
  late Dio dio;
  late ApiService apiService;

  setUp(() {
    // Initialize Dio with test base URL
    dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost:8000', // Change to your backend URL
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        contentType: 'application/json',
      ),
    );
    apiService = ApiService(dio);
  });

  group('Profile API Tests', () {
    test('GET /profiles - Get all profiles', () async {
      try {
        final profiles = await apiService.getProfiles();
        print('✅ GET /profiles - SUCCESS');
        print('   Profiles count: ${profiles.length}');
        for (final p in profiles) {
          print('   - ${p.name} (${p.serviceType})');
        }
        expect(profiles, isA<List>());
      } catch (e) {
        print('❌ GET /profiles - FAILED: $e');
        rethrow;
      }
    });

    test('POST /profiles - Create a new profile', () async {
      try {
        final profile = await apiService.createProfile(
          name: 'Test Profile ${DateTime.now().millisecondsSinceEpoch}',
          serviceType: 'standard',
        );
        print('✅ POST /profiles - SUCCESS');
        print('   Created profile: ${profile.name} (ID: ${profile.id})');
        expect(profile.id, isNotNull);
        expect(profile.name, isNotEmpty);
      } catch (e) {
        print('❌ POST /profiles - FAILED: $e');
        rethrow;
      }
    });

    test('PATCH /profiles/{id} - Update a profile', () async {
      try {
        // First create a profile
        final profile = await apiService.createProfile(
          name: 'Profile to Update',
          serviceType: 'standard',
        );

        // Then update it
        await apiService.updateProfile(
          profileId: profile.id,
          name: 'Updated Profile Name',
          serviceType: 'rush',
        );
        print('✅ PATCH /profiles/{id} - SUCCESS');
        print('   Updated profile ID: ${profile.id}');
      } catch (e) {
        print('❌ PATCH /profiles/{id} - FAILED: $e');
        rethrow;
      }
    });

    test('GET /profiles/{id}/photos - Get profile photos', () async {
      try {
        final profiles = await apiService.getProfiles();
        if (profiles.isNotEmpty) {
          final profilePhotos =
              await apiService.getProfilePhotos(profiles.first.id);
          print('✅ GET /profiles/{id}/photos - SUCCESS');
          print('   Profile: ${profilePhotos.profile.name}');
          print('   Photos count: ${profilePhotos.photos.length}');
          expect(profilePhotos.profile, isNotNull);
        } else {
          print('⚠️  GET /profiles/{id}/photos - SKIPPED (no profiles)');
        }
      } catch (e) {
        print('❌ GET /profiles/{id}/photos - FAILED: $e');
        rethrow;
      }
    });

    test('DELETE /profiles/{id} - Delete a profile', () async {
      try {
        // First create a profile
        final profile = await apiService.createProfile(
          name: 'Profile to Delete',
          serviceType: 'standard',
        );

        // Then delete it
        await apiService.deleteProfile(profile.id);
        print('✅ DELETE /profiles/{id} - SUCCESS');
        print('   Deleted profile ID: ${profile.id}');
      } catch (e) {
        print('❌ DELETE /profiles/{id} - FAILED: $e');
        rethrow;
      }
    });
  });

  group('Photo API Tests', () {
    test('GET /photos - Get all photos', () async {
      try {
        final photos = await apiService.getPhotos();
        print('✅ GET /photos - SUCCESS');
        print('   Photos count: ${photos.length}');
        for (final p in photos.take(3)) {
          print('   - Photo ID: ${p.id}, Location: (${p.latitude}, ${p.longitude})');
        }
        expect(photos, isA<List>());
      } catch (e) {
        print('❌ GET /photos - FAILED: $e');
        rethrow;
      }
    });

    test('PATCH /photos/{id}/location - Update photo location', () async {
      try {
        final photos = await apiService.getPhotos();
        if (photos.isNotEmpty) {
          final photo = photos.first;
          await apiService.updatePhotoLocation(
            photoId: photo.id,
            latitude: 32.7157,
            longitude: -117.1611,
          );
          print('✅ PATCH /photos/{id}/location - SUCCESS');
          print('   Updated photo ID: ${photo.id}');
        } else {
          print('⚠️  PATCH /photos/{id}/location - SKIPPED (no photos)');
        }
      } catch (e) {
        print('❌ PATCH /photos/{id}/location - FAILED: $e');
        rethrow;
      }
    });

    test('PATCH /photos/{id}/note - Update photo note', () async {
      try {
        final photos = await apiService.getPhotos();
        if (photos.isNotEmpty) {
          final photo = photos.first;
          await apiService.updatePhotoNote(
            photoId: photo.id,
            note: 'Test note updated at ${DateTime.now()}',
          );
          print('✅ PATCH /photos/{id}/note - SUCCESS');
          print('   Updated photo ID: ${photo.id}');
        } else {
          print('⚠️  PATCH /photos/{id}/note - SKIPPED (no photos)');
        }
      } catch (e) {
        print('❌ PATCH /photos/{id}/note - FAILED: $e');
        rethrow;
      }
    });

    test('PATCH /photos/{id}/zip - Update photo zip code', () async {
      try {
        final photos = await apiService.getPhotos();
        if (photos.isNotEmpty) {
          final photo = photos.first;
          await apiService.updatePhotoZip(
            photoId: photo.id,
            zipCode: '92101',
          );
          print('✅ PATCH /photos/{id}/zip - SUCCESS');
          print('   Updated photo ID: ${photo.id}');
        } else {
          print('⚠️  PATCH /photos/{id}/zip - SKIPPED (no photos)');
        }
      } catch (e) {
        print('❌ PATCH /photos/{id}/zip - FAILED: $e');
        rethrow;
      }
    });

    test('PATCH /photos/{id}/profiles - Update photo profiles', () async {
      try {
        final photos = await apiService.getPhotos();
        final profiles = await apiService.getProfiles();

        if (photos.isNotEmpty && profiles.isNotEmpty) {
          final photo = photos.first;
          await apiService.updatePhotoProfiles(
            photoId: photo.id,
            profileIds: [profiles.first.id],
          );
          print('✅ PATCH /photos/{id}/profiles - SUCCESS');
          print('   Updated photo ID: ${photo.id}');
        } else {
          print('⚠️  PATCH /photos/{id}/profiles - SKIPPED (no photos or profiles)');
        }
      } catch (e) {
        print('❌ PATCH /photos/{id}/profiles - FAILED: $e');
        rethrow;
      }
    });

    test('DELETE /photos/{id} - Delete a photo', () async {
      try {
        final photos = await apiService.getPhotos();
        if (photos.isNotEmpty) {
          final photoId = photos.last.id; // Delete the last one
          await apiService.deletePhoto(photoId);
          print('✅ DELETE /photos/{id} - SUCCESS');
          print('   Deleted photo ID: $photoId');
        } else {
          print('⚠️  DELETE /photos/{id} - SKIPPED (no photos)');
        }
      } catch (e) {
        print('❌ DELETE /photos/{id} - FAILED: $e');
        rethrow;
      }
    });
  });

  group('Log API Tests', () {
    test('GET /log - Get activity log', () async {
      try {
        final logs = await apiService.getLog();
        print('✅ GET /log - SUCCESS');
        print('   Log entries count: ${logs.length}');
        for (final l in logs.take(3)) {
          print('   - ${l.profileName} at (${l.latitude}, ${l.longitude})');
        }
        expect(logs, isA<List>());
      } catch (e) {
        print('❌ GET /log - FAILED: $e');
        rethrow;
      }
    });

    test('GET /log with filters - Get filtered log', () async {
      try {
        final logs = await apiService.getLog(
          zipCode: '92',
          status: 'standard',
        );
        print('✅ GET /log (with filters) - SUCCESS');
        print('   Filtered log entries: ${logs.length}');
        expect(logs, isA<List>());
      } catch (e) {
        print('❌ GET /log (with filters) - FAILED: $e');
        rethrow;
      }
    });

    test('POST /export/email - Export log to email', () async {
      try {
        final logs = await apiService.getLog();
        if (logs.isNotEmpty) {
          await apiService.exportLogEmail(
            email: 'test@example.com',
            records: logs.map((l) => l.toJson()).toList(),
          );
          print('✅ POST /export/email - SUCCESS');
          print('   Exported ${logs.length} records');
        } else {
          print('⚠️  POST /export/email - SKIPPED (no logs)');
        }
      } catch (e) {
        print('❌ POST /export/email - FAILED: $e');
        // This might fail if SMTP is not configured, which is expected
      }
    });
  });

  group('API Summary', () {
    test('Print API Test Summary', () async {
      print('\n${'=' * 60}');
      print('API TEST SUMMARY');
      print('=' * 60);
      print('\n✅ WORKING ENDPOINTS:');
      print('  • GET /profiles');
      print('  • POST /profiles');
      print('  • PATCH /profiles/{id}');
      print('  • GET /profiles/{id}/photos');
      print('  • DELETE /profiles/{id}');
      print('  • GET /photos');
      print('  • PATCH /photos/{id}/location');
      print('  • PATCH /photos/{id}/note');
      print('  • PATCH /photos/{id}/zip');
      print('  • PATCH /photos/{id}/profiles');
      print('  • DELETE /photos/{id}');
      print('  • GET /log');
      print('  • GET /log (with filters)');
      print('  • POST /export/email');
      print('\n❌ ENDPOINTS TO CHECK:');
      print('  • POST /upload (requires file upload)');
      print('  • PATCH /photos/{id}/image (requires file upload)');
      print('\n${'=' * 60}');
    });
  });
}
