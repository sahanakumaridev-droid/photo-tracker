import 'package:geolocator/geolocator.dart';

import '../../data/models/photo_model.dart';
import '../../data/models/profile_model.dart';
import 'spoken_parser.dart';

class CopilotAction {
  const CopilotAction({
    required this.text,
    this.route,
    this.createDraft,
  });

  final String text;
  final String? route;
  final SpokenDraft? createDraft;
}

class CopilotContext {
  const CopilotContext({
    required this.profiles,
    required this.photos,
    this.earnings,
    this.position,
  });

  final List<ProfileModel> profiles;
  final List<PhotoModel> photos;
  final Map<String, dynamic>? earnings;
  final Position? position;
}

/// On-device copilot: live job/earnings answers plus a few navigable actions.
CopilotAction answerCopilot(String raw, CopilotContext ctx) {
  final q = raw.trim();
  final l = q.toLowerCase();

  if (_wantsCreate(l)) {
    final draft = parseSpokenDraft(q);
    if (draft.name != null && draft.name!.trim().length >= 2) {
      return CopilotAction(
        text: _createPreview(draft),
        createDraft: draft,
      );
    }
    return const CopilotAction(
      text: 'Say it like “Create Jane Doe, First Legal, 125 dollars” and I’ll '
          'fill a new profile for you.',
    );
  }

  if (_any(l, ['earn', 'paid', 'payout', 'money', 'available', 'make'])) {
    return CopilotAction(text: _earningsReply(ctx, l), route: '/earnings');
  }

  if (_any(l, ['closest', 'nearest', 'near me', 'next job', 'next up'])) {
    return CopilotAction(text: _closestReply(ctx), route: '/map');
  }

  if (_any(l, ['upload', 'attempt', 'photo', 'how do i add'])) {
    return const CopilotAction(
      text: 'Open Upload → New Profile (or pick one) → Add Attempt. '
          'Talk the note in — tap the mic instead of typing. A profile can '
          'hold five attempts.',
      route: '/upload',
    );
  }

  if (_any(l, ['search', 'find', 'zip', 'county', 'job #', 'job number'])) {
    return const CopilotAction(
      text: 'On Home, tap the mic next to search and say a name or ZIP. '
          'Log and Jobs have the same talk-to-search mic.',
      route: '/map',
    );
  }

  if (_any(l, ['log', 'export', 'excel', 'sheet'])) {
    return const CopilotAction(
      text: 'Log lists today’s work. Tap a card to open it. Long-press to '
          'export one record, or Select for a multi-record Excel export.',
      route: '/log',
    );
  }

  if (_any(l, ['schedule', 'asap', 'next day', 'queue'])) {
    return const CopilotAction(
      text: 'Schedule groups open work by ASAP, Next Day, Standard, and '
          'Special so you can knock out the hottest jobs first.',
      route: '/schedule',
    );
  }

  if (_any(l, ['route', 'map', 'navigate', 'pin'])) {
    return const CopilotAction(
      text: 'Home is the map. Yellow pins still need an attempt. Tap a pin to '
          'add one, or tap the sparkle to ask me what’s next.',
      route: '/map',
    );
  }

  if (_any(l, ['profile'])) {
    return const CopilotAction(
      text: 'Settings → Manage Profiles, or speak “Create [name], [company], '
          '[pay] dollars” here and I’ll set it up.',
      route: '/profiles-list',
    );
  }

  return CopilotAction(
    text: 'I can talk-fill fields, create a profile from a sentence, find the '
        'closest job, and explain earnings.\n\n'
        'Try: “How much is available?”, “What’s closest?”, or '
        '“Create John Smith, First Legal, 125 dollars”.\n\n'
        '${_snapshot(ctx)}',
  );
}

bool _wantsCreate(String l) =>
    (l.contains('create') ||
        l.contains('add profile') ||
        l.contains('new profile') ||
        l.startsWith('add ')) &&
    !l.contains('attempt');

String _createPreview(SpokenDraft d) {
  final bits = <String>[
    'I’ll create **${d.name}**',
    if (d.companyId != null) companyLabel(d.companyId),
    if (d.payRate != null) '\$${d.payRate} pay',
    if (d.priority != null) d.priority!.replaceAll('_', ' '),
    if (d.address != null) d.address!,
  ];
  return '${bits.join(' · ')}.\nTap Create to save it — no extra typing.';
}

String _earningsReply(CopilotContext ctx, String l) {
  final e = ctx.earnings;
  final available = (e?['available_earnings'] as num?) ??
      ctx.profiles.fold<int>(0, (s, p) => s + (p.payRate ?? 0));
  final earned = (e?['total_earnings'] as num?) ?? 0;
  final jobs = (e?['jobs_completed'] as num?) ?? 0;
  final period = (e?['period'] as String?) ?? 'week';

  if (l.contains('available') || l.contains('open')) {
    final named = ctx.profiles.where((p) => (p.payRate ?? 0) > 0).toList();
    final names =
        named.take(3).map((p) => '${p.name} (\$${p.payRate})').join(', ');
    return 'The big number is money you already completed this period '
        '(\$${earned.round()}).\n\n'
        'Pay on unfinished jobs (\$${available.round()}) is listed separately — '
        'it is not a payout. '
        '${names.isEmpty ? '' : 'Open: $names.'}';
  }

  return 'This $period you completed **\$${earned.round()}** across $jobs '
      'attempt${jobs == 1 ? '' : 's'}.\n'
      'Unfinished jobs still have \$${available.round()} assigned — that is '
      'not cash-out money. I’ll open Earnings.';
}

String _closestReply(CopilotContext ctx) {
  final pos = ctx.position;
  if (pos == null) {
    return 'Turn on location and I’ll pick the nearest open job. '
        'Profiles on Home already sort nearest-first when GPS is on.';
  }
  ProfileModel? best;
  double? bestMi;
  for (final p in ctx.profiles) {
    if (!p.hasLocation) continue;
    final m = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      p.latitude!,
      p.longitude!,
    );
    final mi = m / 1609.34;
    if (bestMi == null || mi < bestMi) {
      bestMi = mi;
      best = p;
    }
  }
  if (best == null) {
    return 'No profile has a map pin yet. Open a profile and set its location, '
        'or tap the map to drop one.';
  }
  final dist = bestMi! < 0.1
      ? 'right next to you'
      : bestMi < 10
          ? '${bestMi.toStringAsFixed(1)} miles away'
          : '${bestMi.round()} miles away';
  final pay = best.payRate != null ? ' · \$${best.payRate}' : '';
  return 'Closest open job: **${best.name}** ($dist$pay). '
      'I’ll take you to the map — tap the pin to add an attempt.';
}

String _snapshot(CopilotContext ctx) {
  final open = ctx.profiles.length;
  return 'Right now you have $open profile${open == 1 ? '' : 's'} on file.';
}

bool _any(String hay, List<String> needles) =>
    needles.any(hay.contains);
