/// Search / display helpers for profile name, job number, ZIP, and county.
class PlaceSearch {
  static final _zip = RegExp(r',?\s*\b\d{5}(?:-\d{4})?\b');
  static final _county = RegExp(
    r"([A-Za-z][A-Za-z .'\-]*\s+County)",
    caseSensitive: false,
  );

  static String countyOf({
    String? address,
    String? city,
    String? extra,
  }) {
    final blob = [address, city, extra]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' ');
    final m = _county.firstMatch(blob);
    return (m?.group(1) ?? '').trim();
  }

  /// Address for swipe-up / cards — ZIP stripped.
  static String withoutZip(String address) {
    var s = address.replaceAll(_zip, '');
    s = s.replaceAll(RegExp(r',\s*,'), ',');
    s = s.replaceAll(RegExp(r'[,\s]+$'), '');
    return s.trim();
  }

  static bool matches({
    required String query,
    required Iterable<String?> fields,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = fields
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ')
        .toLowerCase();
    return hay.contains(q);
  }
}
