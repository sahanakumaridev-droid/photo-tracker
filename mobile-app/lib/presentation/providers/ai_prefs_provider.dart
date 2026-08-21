import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight in-session AI toggles. Settings and the map both read these.
final aiSmartSuggestionsProvider = StateProvider<bool>((ref) => true);
final aiAutoTagProvider = StateProvider<bool>((ref) => true);
final aiDataUsageProvider = StateProvider<bool>((ref) => false);
