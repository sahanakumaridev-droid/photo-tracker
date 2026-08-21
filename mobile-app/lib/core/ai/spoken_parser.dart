import '../../data/models/company.dart';

/// Structured fields pulled out of one spoken or typed sentence.
class SpokenDraft {
  const SpokenDraft({
    this.name,
    this.companyId,
    this.payRate,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.note,
    this.priority,
  });

  final String? name;
  final String? companyId;
  final int? payRate;
  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? note;
  final String? priority;

  bool get isEmpty =>
      name == null &&
      companyId == null &&
      payRate == null &&
      address == null &&
      city == null &&
      state == null &&
      postalCode == null &&
      (note == null || note!.isEmpty) &&
      priority == null;
}

final _zipRe = RegExp(r'\b(\d{5})(?:-\d{4})?\b');
final _dollarRe = RegExp(
  r'(?:\$\s*(\d{1,5})|(\d{1,5})\s*(?:dollars?|bucks?|usd)\b)',
  caseSensitive: false,
);
final _stateRe = RegExp(
  r'\b(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\b',
);

const _numberWords = <String, int>{
  'zero': 0,
  'oh': 0,
  'a': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

/// Parse a field-worker utterance into profile / pay / address pieces.
///
/// Examples:
/// - "John Smith, First Legal, one twenty five dollars"
/// - "Jane Doe 123 Main Street Los Angeles CA 90012 ASAP"
/// - "Rockstar, fifty dollars, no answer at the door"
SpokenDraft parseSpokenDraft(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const SpokenDraft();

  String? companyId;
  String? priority;
  int? payRate;
  String? postalCode;
  String? state;
  String? note;

  final lower = text.toLowerCase();

  if (lower.contains('first legal') || lower.contains('firstlegal')) {
    companyId = 'first_legal';
    text = text.replaceAll(
        RegExp(r'first\s*legal', caseSensitive: false), ' ');
  } else if (lower.contains('rockstar')) {
    companyId = 'rockstar';
    text = text.replaceAll(RegExp(r'rockstar(?:\s+process(?:\s+serving)?)?',
        caseSensitive: false), ' ');
  } else if (RegExp(r'\bknox\b', caseSensitive: false).hasMatch(text)) {
    companyId = 'knox';
    text = text.replaceAll(
        RegExp(r'knox(?:\s+attorney(?:\s+service)?)?', caseSensitive: false),
        ' ');
  }

  if (RegExp(r'\basap\b', caseSensitive: false).hasMatch(text)) {
    priority = 'asap';
    text = text.replaceAll(RegExp(r'\basap\b', caseSensitive: false), ' ');
  } else if (RegExp(r'\bnext\s*day\b', caseSensitive: false).hasMatch(text)) {
    priority = 'next_day';
    text = text.replaceAll(RegExp(r'\bnext\s*day\b', caseSensitive: false), ' ');
  } else if (RegExp(r'\bspecial\b', caseSensitive: false).hasMatch(text)) {
    priority = 'special';
    text = text.replaceAll(RegExp(r'\bspecial\b', caseSensitive: false), ' ');
  } else if (RegExp(r'\bstandard\b', caseSensitive: false).hasMatch(text)) {
    priority = 'standard';
    text = text.replaceAll(RegExp(r'\bstandard\b', caseSensitive: false), ' ');
  }

  final dollar = _dollarRe.firstMatch(text);
  if (dollar != null) {
    payRate = int.tryParse(dollar.group(1) ?? dollar.group(2) ?? '');
    text = text.replaceRange(dollar.start, dollar.end, ' ');
  } else {
    payRate = _spokenDollars(text);
    if (payRate != null) {
      text = text.replaceAll(
        RegExp(
          r'\b(?:a\s+)?(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|and|-|\s)+\s*(?:dollars?|bucks?)?\b',
          caseSensitive: false,
        ),
        ' ',
      );
    }
  }

  final zip = _zipRe.firstMatch(text);
  if (zip != null) {
    postalCode = zip.group(1);
    text = text.replaceRange(zip.start, zip.end, ' ');
  }

  final st = _stateRe.firstMatch(text);
  if (st != null) {
    state = st.group(1);
    text = text.replaceRange(st.start, st.end, ' ');
  }

  text = text
      .replaceAll(
          RegExp(
              r'\b(?:create|add|new|profile|named|name is|pay(?:\s*rate)?|payout|dollars?|bucks?|company|for)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'[,.]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String? address;
  String? city;
  String? name;

  final street = RegExp(
    r'(\d{1,6}\s+.+)$',
  ).firstMatch(text);
  if (street != null) {
    address = _title(street.group(1)!.trim());
    text = text.substring(0, street.start).trim();
  }

  // A leftover two-word tail after a name is often a city.
  final bits = text.split(' ').where((w) => w.isNotEmpty).toList();
  if (address != null && bits.length >= 3) {
    city = _title(bits.sublist(bits.length - 1).join(' '));
    name = _title(bits.sublist(0, bits.length - 1).join(' '));
  } else if (bits.isNotEmpty) {
    name = _title(bits.join(' '));
  }

  if (name != null && name.length < 2) name = null;

  return SpokenDraft(
    name: name,
    companyId: companyId,
    payRate: payRate,
    address: address,
    city: city,
    state: state,
    postalCode: postalCode,
    note: note,
    priority: priority,
  );
}

int? _spokenDollars(String text) {
  final words = text
      .toLowerCase()
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var total = 0;
  var current = 0;
  var saw = false;
  for (final w in words) {
    if (w == 'and') continue;
    if (w == 'hundred') {
      current = (current == 0 ? 1 : current) * 100;
      saw = true;
      continue;
    }
    if (w == 'thousand') {
      current = (current == 0 ? 1 : current) * 1000;
      total += current;
      current = 0;
      saw = true;
      continue;
    }
    final n = _numberWords[w];
    if (n == null) {
      if (saw && current > 0) break;
      continue;
    }
    current += n;
    saw = true;
  }
  total += current;
  if (!saw || total <= 0 || total > 99999) return null;
  return total;
}

String _title(String s) {
  return s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String companyLabel(String? id) => companyOrDefault(id).name;
