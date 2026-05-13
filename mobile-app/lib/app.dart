import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/router/app_router.dart';

class PhotoTrackerApp extends ConsumerWidget {
  const PhotoTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Geo Tag',
      theme: AppTheme.lightTheme(themeState.accentColor),
      darkTheme: AppTheme.darkTheme(themeState.accentColor),
      themeMode: themeState.mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
