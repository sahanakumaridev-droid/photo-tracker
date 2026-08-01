import '../../core/utils/category.dart';

/// Time-of-day window for a diligence attempt slot.
class TimeInterval {
  const TimeInterval({required this.start, required this.end});

  final String start;
  final String end;

  String get label => '$start – $end';

  Map<String, String> toJson() => {'start': start, 'end': end};

  factory TimeInterval.fromJson(Map<String, dynamic> json) => TimeInterval(
        start: json['start'] as String,
        end: json['end'] as String,
      );
}

/// Morning / midday / evening attempt windows for a [Company].
class CompanyTimeIntervals {
  const CompanyTimeIntervals({
    required this.morning,
    required this.midday,
    required this.evening,
  });

  final TimeInterval morning;
  final TimeInterval midday;
  final TimeInterval evening;

  Map<String, dynamic> toJson() => {
        'morning': morning.toJson(),
        'midday': midday.toJson(),
        'evening': evening.toJson(),
      };

  factory CompanyTimeIntervals.fromJson(Map<String, dynamic> json) =>
      CompanyTimeIntervals(
        morning: TimeInterval.fromJson(json['morning'] as Map<String, dynamic>),
        midday: TimeInterval.fromJson(json['midday'] as Map<String, dynamic>),
        evening: TimeInterval.fromJson(json['evening'] as Map<String, dynamic>),
      );
}

/// Process-serving company configuration. Hardcoded for now; keyed by [id]
/// so profiles can store a stable reference without duplicating rate tables.
class Company {
  const Company({
    required this.id,
    required this.name,
    required this.email,
    required this.attemptsForDiligence,
    required this.payoutSchedule,
    required this.payRateStructure,
    required this.timeIntervals,
    required this.availablePriorityLevels,
  });

  /// Stable slug stored on Profile.company (e.g. `first_legal`).
  final String id;
  final String name;
  final String email;
  final int attemptsForDiligence;

  /// Day-of-month payouts (e.g. `[10, 25]`), or — when
  /// `payoutSchedule[0] > payoutSchedule[1]` — start day-of-month plus a
  /// week interval (Knox: `[31, 2]` ⇒ every 2 weeks from Jul 31, 2026).
  final List<int> payoutSchedule;

  /// Human-readable pay rules keyed by priority value (`standard`, `asap`, …).
  final Map<String, String> payRateStructure;

  final CompanyTimeIntervals timeIntervals;

  /// Priority category values this company allows (subset of [kPhotoCategories]).
  final List<String> availablePriorityLevels;

  /// True when [payoutSchedule] encodes biweekly-from-start rather than
  /// fixed calendar days.
  bool get isIntervalPayout =>
      payoutSchedule.length >= 2 && payoutSchedule[0] > payoutSchedule[1];

  String get payoutScheduleDescription {
    if (payoutSchedule.isEmpty) return '';
    if (isIntervalPayout) {
      final startDay = payoutSchedule[0];
      final weeks = payoutSchedule[1];
      return 'Starting day $startDay, every $weeks week(s)';
    }
    final days = payoutSchedule.map(_ordinal).join(' and ');
    return 'The $days of every month';
  }

  /// Priority chips available for this company (preserves display order).
  List<PhotoCategory> get priorityCategories => kPhotoCategories
      .where((c) => availablePriorityLevels.contains(c.value))
      .toList(growable: false);

  bool allowsPriority(String? value) {
    final v = (value ?? kDefaultCategory).toLowerCase();
    return availablePriorityLevels.contains(v);
  }

  String? payRateFor(String? priority) {
    final v = (priority ?? kDefaultCategory).toLowerCase();
    return payRateStructure[v];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'attempts_for_diligence': attemptsForDiligence,
        'payout_schedule': payoutSchedule,
        'pay_rate_structure': payRateStructure,
        'time_intervals': timeIntervals.toJson(),
        'available_priority_levels': availablePriorityLevels,
      };

  static String _ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }
}

// ── Hardcoded companies ─────────────────────────────────────────────────────

const Company kFirstLegal = Company(
  id: 'first_legal',
  name: 'First Legal',
  email: 'sdprocess@firstlegal.com',
  attemptsForDiligence: 6,
  payoutSchedule: [10, 25],
  payRateStructure: {
    'standard': '1st 3 attempts \$18, \$6.50/attempt after',
    'next_day': '1st 3 attempts \$23.50, \$8/attempt after',
    'asap': '1st attempt \$40, \$20/attempt after',
  },
  timeIntervals: CompanyTimeIntervals(
    morning: TimeInterval(start: '7:00 AM', end: '8:00 AM'),
    midday: TimeInterval(start: '11:00 AM', end: '4:00 PM'),
    evening: TimeInterval(start: '5:30 PM', end: '10:00 PM'),
  ),
  availablePriorityLevels: ['standard', 'next_day', 'asap'],
);

const Company kRockstar = Company(
  id: 'rockstar',
  name: 'Rockstar Process Serving',
  email: 'rockstarlegal.sean@gmail.com',
  attemptsForDiligence: 4,
  payoutSchedule: [1, 15],
  payRateStructure: {
    'standard': '\$50',
    'next_day': '\$60',
    'asap': '\$70',
  },
  timeIntervals: CompanyTimeIntervals(
    morning: TimeInterval(start: '7:00 AM', end: '10:00 AM'),
    midday: TimeInterval(start: '11:00 AM', end: '4:00 PM'),
    evening: TimeInterval(start: '6:00 PM', end: '10:00 PM'),
  ),
  availablePriorityLevels: ['standard', 'next_day', 'asap'],
);

const Company kKnox = Company(
  id: 'knox',
  name: 'Knox Attorney Service',
  email: 'sdprocess@knoxservices.com',
  attemptsForDiligence: 5,
  // [31, 2] ⇒ start Jul 31, 2026, every 2 weeks (schedule[0] > schedule[1]).
  payoutSchedule: [31, 2],
  payRateStructure: {
    'standard': '\$30',
    'asap': '\$50',
  },
  timeIntervals: CompanyTimeIntervals(
    morning: TimeInterval(start: '7:00 AM', end: '8:30 AM'),
    midday: TimeInterval(start: '11:00 AM', end: '4:00 PM'),
    evening: TimeInterval(start: '5:30 PM', end: '10:00 PM'),
  ),
  availablePriorityLevels: ['standard', 'asap'],
);

/// All known companies, in display order.
const List<Company> kCompanies = [kFirstLegal, kRockstar, kKnox];

const String kDefaultCompanyId = 'first_legal';

Company? companyById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in kCompanies) {
    if (c.id == id) return c;
  }
  return null;
}

Company companyOrDefault(String? id) =>
    companyById(id) ?? companyById(kDefaultCompanyId)!;

/// Default priority value for a company (prefers Standard when allowed).
String defaultPriorityForCompany(String? companyId) {
  final levels = companyOrDefault(companyId).availablePriorityLevels;
  if (levels.contains(kDefaultCategory)) return kDefaultCategory;
  return levels.isNotEmpty ? levels.first : kDefaultCategory;
}

/// Priority categories allowed for [companyId] (falls back to Standard /
/// Next Day / ASAP when the company is unknown — keeps legacy profiles usable).
List<PhotoCategory> priorityCategoriesForCompany(String? companyId) {
  final company = companyById(companyId);
  if (company == null) {
    return kPhotoCategories
        .where((c) => c.value != 'special')
        .toList(growable: false);
  }
  return company.priorityCategories;
}
