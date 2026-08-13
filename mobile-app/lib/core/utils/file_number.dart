/// Dispatcher file-number helpers shared by upload forms and watermarks.
///
/// File number is required on upload. Users may enter a real number or select
/// the sentinel [kFileNumberNA]. Watermarks substitute the profile name when
/// the value is absent or N/A.
library;

/// Explicit "no file number" choice stored on the attempt/photo.
const String kFileNumberNA = 'N/A';

/// True when [value] is empty or the N/A sentinel (any casing).
bool isAbsentFileNumber(String? value) {
  final v = (value ?? '').trim();
  return v.isEmpty || v.toUpperCase() == 'N/A';
}

/// Watermark / stamp heading: use a real file number when present, otherwise
/// fall back to [profileName] (covers empty and N/A).
String watermarkFileHeading({String? fileNumber, String? profileName}) {
  final fn = (fileNumber ?? '').trim();
  if (fn.isNotEmpty && fn.toUpperCase() != 'N/A') return fn;
  return (profileName ?? '').trim();
}
