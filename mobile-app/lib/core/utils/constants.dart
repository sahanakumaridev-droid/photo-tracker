/// App-wide constants
class AppConstants {
  // Demo credentials
  static const String demoEmail1 = 'admin@geotagging.com';
  static const String demoPassword1 = 'admin123';
  static const String demoEmail2 = 'demo@geotagging.com';
  static const String demoPassword2 = 'demo123';

  // Service types
  static const String serviceTypeRush = 'rush';
  static const String serviceTypeStandard = 'standard';
  static const String serviceTypeAirport = 'airport';

  static const List<String> serviceTypes = [
    serviceTypeStandard,
    serviceTypeRush,
    serviceTypeAirport,
  ];

  // Color codes for service types
  static const Map<String, int> serviceTypeColors = {
    serviceTypeRush: 0xFFef4444,
    serviceTypeStandard: 0xFF10b981,
    serviceTypeAirport: 0xFF0ea5e9,
  };

  // Nominatim API
  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';

  // Default map center (San Francisco)
  static const double defaultMapLat = 37.7749;
  static const double defaultMapLng = -122.4194;
  static const double defaultMapZoom = 13;

  // Location accuracy
  static const double locationAccuracyThreshold = 50; // meters
}
