import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/log_entry_model.dart';
import 'repository_providers.dart';

/// Get activity log with filters
final logProvider = FutureProvider.family<
    List<LogEntryModel>,
    ({String? date, String? zipCode, String? status, String? search})>(
  (ref, filters) async {
    final repository = ref.watch(logRepositoryProvider);
    return repository.getLog(
      date: filters.date,
      zipCode: filters.zipCode,
      status: filters.status,
      search: filters.search,
    );
  },
);

/// Export log to email
final exportLogProvider =
    FutureProvider.family<void, (String, List<Map<String, dynamic>>)>(
  (ref, args) async {
    final repository = ref.watch(logRepositoryProvider);
    await repository.exportLogEmail(
      email: args.$1,
      records: args.$2,
    );
  },
);
