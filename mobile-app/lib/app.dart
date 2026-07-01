import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'core/storage/upload_queue.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/locale_provider.dart';
import 'presentation/providers/photo_provider.dart';
import 'presentation/providers/repository_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/router/app_router.dart';

class PhotoTrackerApp extends ConsumerStatefulWidget {
  const PhotoTrackerApp({super.key});

  @override
  ConsumerState<PhotoTrackerApp> createState() => _PhotoTrackerAppState();
}

class _PhotoTrackerAppState extends ConsumerState<PhotoTrackerApp> {
  @override
  void initState() {
    super.initState();
    // Give the offline queue a way to actually upload: the photo repository.
    // Each queued item carries its own (immutable) timestamp + geotag, which
    // are re-sent verbatim on every retry.
    UploadQueueService.instance.attachUploader((item) async {
      final repo = ref.read(photoRepositoryProvider);
      await repo.uploadPhoto(
        filePath: item.filePath,
        profileId: item.profileId,
        latitude: item.latitude,
        longitude: item.longitude,
        address: item.address,
        note: item.note,
        category: item.category,
        completionType: item.completionType,
        servedTo: item.servedTo,
        payRate: item.payRate,
        takenAt: item.takenAt,
        locationGroupId: item.locationGroupId,
        userId: item.userId,
      );
      // A queued upload landed — refresh the photo list so it appears.
      ref.invalidate(photosProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Geo Tag',
      theme: AppTheme.lightTheme(themeState.accentColor),
      // Dark mode was removed — the app uses a single light theme everywhere.
      themeMode: ThemeMode.light,
      locale: locale,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // App-wide: tapping anywhere outside a text field dismisses the keyboard.
      // Covers every screen (incl. numeric pads like Pay Rate that have no
      // "Done" key on iOS). Translucent hit-testing lets buttons still receive
      // their own taps; only taps on empty space unfocus the active field.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
