import 'dart:math';

import 'package:intl/intl.dart';

extension DateTimeExtensions on DateTime {
  /// Format as "Jan 15, 2024 2:30 PM"
  String toFormattedString() =>
      DateFormat('MMM dd, yyyy h:mm a').format(this);

  /// Format as "2024-01-15"
  String toDateString() => DateFormat('yyyy-MM-dd').format(this);

  /// Format as "2:30 PM"
  String toTimeString() => DateFormat('h:mm a').format(this);

  /// Format as "Jan 15"
  String toMonthDayString() => DateFormat('MMM dd').format(this);
}

extension StringExtensions on String {
  /// Capitalize first letter
  String capitalize() =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);

  /// Check if valid email
  bool isValidEmail() {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(this);
  }

  /// Check if valid zip code (5 digits)
  bool isValidZipCode() => RegExp(r'^\d{5}$').hasMatch(this);
}

extension DoubleExtensions on double {
  /// Format coordinates to 4 decimal places
  String toCoordinateString() => toStringAsFixed(4);

  /// Calculate distance between two points (Haversine formula)
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371; // Earth's radius in km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
