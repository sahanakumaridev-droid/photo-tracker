import 'package:dio/dio.dart';

void main() async {
  print('🔍 Testing API Connection...\n');

  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://24.199.85.230',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );

  try {
    print('📡 Testing GET /profiles...');
    final response = await dio.get('/profiles');
    print('✅ SUCCESS - Status: ${response.statusCode}');
    print('   Response: ${response.data}\n');
  } on DioException catch (e) {
    print('❌ FAILED');
    print('   Type: ${e.type}');
    print('   Message: ${e.message}');
    print('   Status Code: ${e.response?.statusCode}');
    print('   Response: ${e.response?.data}\n');
  } catch (e) {
    print('❌ ERROR: $e\n');
  }

  try {
    print('📡 Testing POST /profiles (Create)...');
    final response = await dio.post(
      '/profiles',
      data: {
        'name': 'Test Profile',
        'service_type': 'standard',
      },
    );
    print('✅ SUCCESS - Status: ${response.statusCode}');
    print('   Response: ${response.data}\n');
  } on DioException catch (e) {
    print('❌ FAILED');
    print('   Type: ${e.type}');
    print('   Message: ${e.message}');
    print('   Status Code: ${e.response?.statusCode}');
    print('   Response: ${e.response?.data}\n');
  } catch (e) {
    print('❌ ERROR: $e\n');
  }

  try {
    print('📡 Testing GET /photos...');
    final response = await dio.get('/photos');
    print('✅ SUCCESS - Status: ${response.statusCode}');
    print('   Response: ${response.data}\n');
  } on DioException catch (e) {
    print('❌ FAILED');
    print('   Type: ${e.type}');
    print('   Message: ${e.message}');
    print('   Status Code: ${e.response?.statusCode}');
    print('   Response: ${e.response?.data}\n');
  } catch (e) {
    print('❌ ERROR: $e\n');
  }

  print('✅ API Test Complete');
}
