import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/profile_model.dart';
import '../providers/auth_provider.dart';
import '../providers/photo_provider.dart';
import '../providers/profile_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/archive/archive_screen.dart';
import '../screens/earnings/earnings_screen.dart';
import '../screens/home/edit_location_screen.dart';
import '../screens/home/home_screen_v2.dart';
import '../screens/home/map_view_screen.dart';
import '../screens/home/photo_detail_screen.dart';
import '../screens/jobs/jobs_screen.dart';
import '../screens/log/log_screen_v2.dart';
import '../screens/more/more_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/settings/profiles_list_screen.dart';
import '../screens/settings/profiles_management_screen.dart';
import '../screens/settings/settings_screen_v2.dart';
import '../screens/profiles/profile_detail_screen.dart';
import '../screens/upload/attempts_dashboard_screen.dart';
import '../screens/upload/resume_attempt_screen.dart';
import '../widgets/common/bottom_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects on auth changes WITHOUT recreating the router (which would
  // reset navigation). A bump on this notifier re-evaluates the redirect.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;

      // Splash owns its own timed branding + first navigation.
      if (location == '/splash') return null;

      if (auth.isAuthenticated) {
        // Logged in — keep the user out of the auth funnel and land on the
        // Home tab (the map view, the default screen for field work). The
        // old feed screen (/home) is reachable via "View List" on the map.
        if (location == '/login' || location == '/onboarding') return '/map';
        return null;
      }

      // Not authenticated: show onboarding until it's been seen, then login.
      if (!auth.seenOnboarding) {
        return location == '/onboarding' ? null : '/onboarding';
      }
      return location == '/login' ? null : '/login';
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreenV2(),
          ),
          GoRoute(
            path: '/map',
            builder: (context, state) => const MapViewScreen(),
          ),
          GoRoute(
            path: '/jobs',
            builder: (context, state) => const JobsScreen(),
          ),
          GoRoute(
            path: '/upload',
            builder: (context, state) {
              final profileId = int.tryParse(
                  state.uri.queryParameters['profileId'] ?? '');
              // "Start Attempt" from a specific Profile — keep skipping
              // straight to the wizard. Otherwise (plain bottom-nav tap):
              // land on the dashboard so an in-progress attempt can be
              // resumed instead of always starting blank.
              if (profileId != null) {
                return ResumeAttemptScreen(initialProfileId: profileId);
              }
              return const AttemptsDashboardScreen();
            },
          ),
          GoRoute(
            path: '/log',
            builder: (context, state) => LogScreenV2(
              initialCategory: state.uri.queryParameters['category'],
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreenV2(),
          ),
          GoRoute(
            path: '/earnings',
            builder: (context, state) => const EarningsScreen(),
          ),
          GoRoute(
            path: '/archive',
            builder: (context, state) => const ArchiveScreen(),
          ),
          GoRoute(
            path: '/schedule',
            builder: (context, state) => const ScheduleScreen(),
          ),
          GoRoute(
            path: '/more',
            builder: (context, state) => const MoreScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/profiles-management',
        builder: (context, state) {
          final profile = state.extra as ProfileModel?;
          return ProfilesManagementScreen(profileToEdit: profile);
        },
      ),
      GoRoute(
        path: '/profiles-list',
        builder: (context, state) => const ProfilesListScreen(),
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return ProfileDetailScreen(profileId: id);
        },
      ),
      GoRoute(
        path: '/photo/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return PhotoDetailScreen(photoId: id);
        },
      ),
      GoRoute(
        path: '/edit-location',
        builder: (context, state) {
          final photo = state.extra as dynamic;
          return EditLocationScreen(photo: photo);
        },
      ),
    ],
  );
});

class _ShellScaffold extends ConsumerStatefulWidget {
  const _ShellScaffold({required this.child});
  final Widget child;

  @override
  ConsumerState<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<_ShellScaffold> {
  // Index map (matches BottomNav): 0 Home (map) · 1 Jobs · 2 Log ·
  // 3 Earnings. Upload lives in each screen's app bar, not the tab bar.
  int _indexForLocation(String loc) {
    if (loc.startsWith('/map')) return 0;
    if (loc.startsWith('/home')) return 0;
    if (loc.startsWith('/jobs')) return 1;
    if (loc.startsWith('/log')) return 2;
    if (loc.startsWith('/earnings')) return 3;
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexForLocation(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNav(
        currentIndex: currentIndex,
        onTap: (index) => _onTabTap(index, currentIndex),
      ),
    );
  }

  void _onTabTap(int index, int currentIndex) {
    // Tapping the current (Home/map) tab again triggers a data refresh.
    if (index == currentIndex && (index == 0 || index == 1)) {
      ref.invalidate(photosProvider);
      ref.invalidate(profilesProvider);
    }
    switch (index) {
      case 0: context.go('/map'); break;
      case 1: context.go('/jobs'); break;
      case 2: context.go('/log'); break;
      case 3: context.go('/earnings'); break;
    }
  }
}
