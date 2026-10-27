import 'package:url_launcher/url_launcher.dart';

/// Opens an external maps app (Google Maps app if installed, otherwise the
/// browser) pointed at a location.
///
/// Prefers the human-readable [address] as the search query — this behaves
/// exactly as if the user copy-pasted the address into Google Maps. When no
/// usable address is available it falls back to the raw [lat],[lng]
/// coordinates so the pin still resolves.
class MapsLauncher {
  const MapsLauncher._();

  /// Returns `true` if Google Maps was launched, `false` if no handler was available.
  static Future<bool> openLocation({
    String? address,
    required double lat,
    required double lng,
  }) async {
    final cleanedAddress = address
        ?.replaceAll('\n', ', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final hasAddress = cleanedAddress != null &&
        cleanedAddress.isNotEmpty &&
        cleanedAddress != 'No address set' &&
        cleanedAddress != 'Location not set' &&
        !RegExp(r'^0\.0+\s*,\s*0\.0+$').hasMatch(cleanedAddress);
    final hasCoords = lat.abs() > 0.0001 || lng.abs() > 0.0001;
    if (!hasAddress && !hasCoords) return false;

    final query = hasAddress
        ? Uri.encodeComponent(cleanedAddress)
        : '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;
    } catch (_) {}
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}
