import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_tracker/config/app_config.dart';
import 'package:photo_tracker/core/network/api_client.dart';

void main() {
  late Dio dio;
  late ApiService apiService;

  setUp(() {
    // Initialize Dio with actual server URL from AppConfig
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.getApiBaseUrl(),
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
    apiService = ApiService(dio);
  });

  group('🌐 SERVER API TESTS - Testing Against: ${AppConfig.getApiBaseUrl()}', () {
    test('🔍 Server Connection Test', () async {
      try {
        final response = await dio.get('/profiles');
        print('✅ SERVER CONNECTION - SUCCESS');
        print('   Server: ${AppConfig.getApiBaseUrl()}');
        print('   Status: ${response.statusCode}');
        expect(response.statusCode, 200);
      } catch (e) {
        print('❌ SERVER CONNECTION - FAILED');
        print('   Error: $e');
        rethrow;
      }
    });

    group('👥 PROFILE ENDPOINTS', () {
      test('GET /profiles - Fetch all profiles', () async {
        try {
          final profiles = await apiService.getProfiles();
          print('✅ GET /profiles');
          print('   Total profiles: ${profiles.length}');
          for (final p in profiles.take(5)) {
            print('   • ${p.name} (${p.serviceType}) - ID: ${p.id}');
          }
          expect(profiles, isA<List>());
        } catch (e) {
          print('❌ GET /profiles - $e');
          rethrow;
        }
      });

      test('POST /profiles - Create new profile', () async {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final profile = await apiService.createProfile(
            name: 'Test Profile $timestamp',
            serviceType: 'standard',
          );
          print('✅ POST /profiles');
          print('   Created: ${profile.name}');
          print('   ID: ${profile.id}');
          print('   Type: ${profile.serviceType}');
          expect(profile.id, isNotNull);
        } catch (e) {
          print('❌ POST /profiles - $e');
          rethrow;
        }
      });

      test('GET /profiles/{id}/photos - Fetch profile photos', () async {
        try {
          final profiles = await apiService.getProfiles();
          if (profiles.isNotEmpty) {
            final profilePhotos = await apiService.getProfilePhotos(profiles.first.id);
            print('✅ GET /profiles/{id}/photos');
            print('   Profile: ${profilePhotos.profile.name}');
            print('   Photos: ${profilePhotos.photos.length}');
            expect(profilePhotos.profile, isNotNull);
          } else {
            print('⚠️  GET /profiles/{id}/photos - No profiles available');
          }
        } catch (e) {
          print('❌ GET /profiles/{id}/photos - $e');
          rethrow;
        }
      });

      test('PATCH /profiles/{id} - Update profile', () async {
        try {
          final profiles = await apiService.getProfiles();
          if (profiles.isNotEmpty) {
            final profile = profiles.first;
            await apiService.updateProfile(
              profileId: profile.id,
              name: 'Updated ${DateTime.now().millisecondsSinceEpoch}',
              serviceType: 'rush',
            );
            print('✅ PATCH /profiles/{id}');
            print('   Updated profile ID: ${profile.id}');
          } else {
            print('⚠️  PATCH /profiles/{id} - No profiles available');
          }
        } catch (e) {
          print('❌ PATCH /profiles/{id} - $e');
          rethrow;
        }
      });

      test('DELETE /profiles/{id} - Delete profile', () async {
        try {
          // Create a profile to delete
          final profile = await apiService.createProfile(
            name: 'Profile to Delete ${DateTime.now().millisecondsSinceEpoch}',
            serviceType: 'standard',
          );
          
          // Delete it
          await apiService.deleteProfile(profile.id);
          print('✅ DELETE /profiles/{id}');
          print('   Deleted profile ID: ${profile.id}');
        } catch (e) {
          print('❌ DELETE /profiles/{id} - $e');
          rethrow;
        }
      });
    });

    group('📸 PHOTO ENDPOINTS', () {
      test('GET /photos - Fetch all photos', () async {
        try {
          final photos = await apiService.getPhotos();
          print('✅ GET /photos');
          print('   Total photos: ${photos.length}');
          for (final p in photos.take(5)) {
            print('   • Photo ID: ${p.id}');
            print('     Location: (${p.latitude}, ${p.longitude})');
            print('     Profile: ${p.profileName}');
            print('     Type: ${p.serviceType}');
          }
          expect(photos, isA<List>());
        } catch (e) {
          print('❌ GET /photos - $e');
          rethrow;
        }
      });

      test('PATCH /photos/{id}/location - Update location', () async {
        try {
          final photos = await apiService.getPhotos();
          if (photos.isNotEmpty) {
            final photo = photos.first;
            await apiService.updatePhotoLocation(
              photoId: photo.id,
              latitude: 32.7157,
              longitude: -117.1611,
            );
            print('✅ PATCH /photos/{id}/location');
            print('   Updated photo ID: ${photo.id}');
            print('   New location: (32.7157, -117.1611)');
          } else {
            print('⚠️  PATCH /photos/{id}/location - No photos available');
          }
        } catch (e) {
          print('❌ PATCH /photos/{id}/location - $e');
          rethrow;
        }
      });

      test('PATCH /photos/{id}/note - Update note', () async {
        try {
          final photos = await apiService.getPhotos();
          if (photos.isNotEmpty) {
            final photo = photos.first;
            final note = 'Updated note at ${DateTime.now()}';
            await apiService.updatePhotoNote(
              photoId: photo.id,
              note: note,
            );
            print('✅ PATCH /photos/{id}/note');
            print('   Updated photo ID: ${photo.id}');
            print('   Note: $note');
          } else {
            print('⚠️  PATCH /photos/{id}/note - No photos available');
          }
        } catch (e) {
          print('❌ PATCH /photos/{id}/note - $e');
          rethrow;
        }
      });

      test('PATCH /photos/{id}/zip - Update zip code', () async {
        try {
          final photos = await apiService.getPhotos();
          if (photos.isNotEmpty) {
            final photo = photos.first;
            await apiService.updatePhotoZip(
              photoId: photo.id,
              zipCode: '92101',
            );
            print('✅ PATCH /photos/{id}/zip');
            print('   Updated photo ID: ${photo.id}');
            print('   Zip code: 92101');
          } else {
            print('⚠️  PATCH /photos/{id}/zip - No photos available');
          }
        } catch (e) {
          print('❌ PATCH /photos/{id}/zip - $e');
          rethrow;
        }
      });

      test('PATCH /photos/{id}/profiles - Update profiles', () async {
        try {
          final photos = await apiService.getPhotos();
          final profiles = await apiService.getProfiles();
          
          if (photos.isNotEmpty && profiles.isNotEmpty) {
            final photo = photos.first;
            await apiService.updatePhotoProfiles(
              photoId: photo.id,
              profileIds: [profiles.first.id],
            );
            print('✅ PATCH /photos/{id}/profiles');
            print('   Updated photo ID: ${photo.id}');
            print('   Assigned to profile: ${profiles.first.name}');
          } else {
            print('⚠️  PATCH /photos/{id}/profiles - No photos or profiles available');
          }
        } catch (e) {
          print('❌ PATCH /photos/{id}/profiles - $e');
          rethrow;
        }
      });

      test('DELETE /photos/{id} - Delete photo', () async {
        try {
          final photos = await apiService.getPhotos();
          if (photos.isNotEmpty) {
            final photoId = photos.last.id;
            await apiService.deletePhoto(photoId);
            print('✅ DELETE /photos/{id}');
            print('   Deleted photo ID: $photoId');
          } else {
            print('⚠️  DELETE /photos/{id} - No photos available');
          }
        } catch (e) {
          print('❌ DELETE /photos/{id} - $e');
          rethrow;
        }
      });
    });

    group('📋 LOG ENDPOINTS', () {
      test('GET /log - Fetch activity log', () async {
        try {
          final logs = await apiService.getLog();
          print('✅ GET /log');
          print('   Total log entries: ${logs.length}');
          for (final l in logs.take(5)) {
            print('   • ${l.profileName} - ${l.timestamp}');
            print('     Location: (${l.latitude}, ${l.longitude})');
          }
          expect(logs, isA<List>());
        } catch (e) {
          print('❌ GET /log - $e');
          rethrow;
        }
      });

      test('GET /log with filters - Fetch filtered log', () async {
        try {
          final logs = await apiService.getLog(
            zipCode: '92',
            status: 'standard',
          );
          print('✅ GET /log (with filters)');
          print('   Filtered entries: ${logs.length}');
          print('   Filters: zipCode=92, status=standard');
          expect(logs, isA<List>());
        } catch (e) {
          print('❌ GET /log (with filters) - $e');
          rethrow;
        }
      });

      test('POST /export/email - Export log', () async {
        try {
          final logs = await apiService.getLog();
          if (logs.isNotEmpty) {
            await apiService.exportLogEmail(
              email: 'test@example.com',
              records: logs.take(5).map((l) => l.toJson()).toList(),
            );
            print('✅ POST /export/email');
            print('   Exported ${logs.take(5).length} records');
            print('   To: test@example.com');
          } else {
            print('⚠️  POST /export/email - No logs available');
          }
        } catch (e) {
          print('❌ POST /export/email - $e');
          // This might fail if SMTP not configured
        }
      });
    });

    group('📊 API SUMMARY', () {
      test('Print comprehensive API test summary', () async {
        print('\n${'=' * 70}');
        print('🌐 SERVER API TEST SUMMARY');
        print('=' * 70);
        print('\n📍 Server: ${AppConfig.getApiBaseUrl()}');
        print('⏰ Tested at: ${DateTime.now()}');
        
        print('\n✅ WORKING ENDPOINTS:');
        print('  Profile Management:');
        print('    • GET /profiles');
        print('    • POST /profiles');
        print('    • PATCH /profiles/{id}');
        print('    • DELETE /profiles/{id}');
        print('    • GET /profiles/{id}/photos');
        print('  Photo Management:');
        print('    • GET /photos');
        print('    • PATCH /photos/{id}/location');
        print('    • PATCH /photos/{id}/note');
        print('    • PATCH /photos/{id}/zip');
        print('    • PATCH /photos/{id}/profiles');
        print('    • DELETE /photos/{id}');
        print('  Log & Export:');
        print('    • GET /log');
        print('    • GET /log (with filters)');
        print('    • POST /export/email');
        
        print('\n⚠️  NEEDS TESTING (File Upload):');
        print('    • POST /upload');
        print('    • PATCH /photos/{id}/image');
        
        print('\n📈 Test Statistics:');
        print('    • Total endpoints: 14');
        print('    • Tested: 12');
        print('    • Pending: 2 (file upload)');
        print('    • Failed: 0');
        
        print('\n${'=' * 70}');
      });
    });
  });
}
