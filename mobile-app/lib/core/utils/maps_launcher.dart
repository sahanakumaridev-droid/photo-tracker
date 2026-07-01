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

  /// Returns `true` if maps was launched, `false` if no handler was available.
  static Future<bool> openLocation({
    String? address,
    required double lat,
    required double lng,
  }) async {
    final hasAddress = address != null && address.trim().isNotEmpty;
    final query = hasAddress
        ? Uri.encodeComponent(address.trim())
        : '$lat,$lng';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
